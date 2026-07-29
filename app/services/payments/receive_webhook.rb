# frozen_string_literal: true

module Payments
  class ReceiveWebhook < ApplicationService
    RECEIVED_RECLAIM_AFTER = 1.minute
    STRIPE_IDENTITY_UNAVAILABLE_CODE = "provider_identity_unavailable"
    STRIPE_IDENTITY_RETRY_AFTER = 60

    def initialize(provider:, event_id:, event_type:, payload:, signature:, headers: {})
      @provider = provider.to_s
      @event_id = event_id.to_s
      @event_type = event_type.to_s
      @payload = payload
      @signature = signature.to_s
      @headers = headers.to_h
    end

    def call
      unless valid_identifier?(@event_id) && valid_identifier?(@event_type)
        return ServiceResult.failure(
          error: :webhook_event_identifiers_are_invalid,
          code: "invalid_event_identifier"
        )
      end

      adapter = Payments::Provider.for(@provider)
      return receive_with_stripe_identity_lock(adapter) if @provider == "stripe"

      receive_verified_event(adapter)
    rescue Payments::Provider::UnknownProviderError => error
      ServiceResult.failure(error: error.message, code: "unknown_provider")
    rescue Payments::WebhookPayload::InvalidPayloadError => error
      ServiceResult.failure(error: error.message, code: "invalid_payload")
    end

    private

    def receive_with_stripe_identity_lock(adapter)
      result = nil

      Payments::ProviderConfig.transaction do
        config = Payments::ProviderConfig.lock.find_by(provider: "stripe")
        unless config&.reconciliation_ready?
          result = ServiceResult.failure(
            error: :stripe_account_identity_is_not_ready,
            code: STRIPE_IDENTITY_UNAVAILABLE_CODE,
            retry_after: STRIPE_IDENTITY_RETRY_AFTER
          )
          next
        end

        result = receive_verified_event(adapter)
      end

      result
    end

    def receive_verified_event(adapter)
      payload_body = @payload.is_a?(String) ? @payload : @payload.to_json
      signature_bypassed =
        Mcweb::DeveloperMode.allow?(:skip_inbound_webhook_signatures)

      unless signature_bypassed || adapter.verify_webhook_signature(
        payload: payload_body,
        signature: @signature,
        headers: @headers
      )
        return ServiceResult.failure(
          error: :invalid_webhook_signature,
          code: "invalid_signature"
        )
      end

      normalized_payload = Payments::WebhookPayload.normalize(
        provider: @provider,
        event_id: @event_id,
        event_type: @event_type,
        payload: @payload
      )
      payload_digest = Payments::WebhookPayload.digest(
        normalized_payload,
        event_type: @event_type
      )

      result = persist_verified_event(
        normalized_payload,
        payload_digest,
        signature_bypassed: signature_bypassed
      )
      instrument_signature_bypass if signature_bypassed && result.success?
      result
    end

    def persist_verified_event(normalized_payload, payload_digest, signature_bypassed:)
      should_process = false
      idempotent = false
      mismatch = false
      newly_created = false

      event = Payments::WebhookEvent.transaction do
        scope = Payments::WebhookEvent.lock
        record = scope.find_by(provider: @provider, event_id: @event_id)
        unless record
          record = create_event_or_find_concurrent!(
            scope,
            normalized_payload,
            payload_digest
          )
          newly_created = record.previously_new_record?
        end

        if record.payload_digest.present? && !same_digest?(record.payload_digest, payload_digest)
          mismatch = true
          next record
        end

        record.assign_attributes(
          event_type: @event_type,
          payload: normalized_payload,
          payload_digest: payload_digest,
          verified_at: Time.current
        )

        if record.processed? || record.dead_letter?
          idempotent = true
        elsif record.processing? && !record.processing_stale?
          idempotent = true
        elsif record.received? && !newly_created &&
            record.updated_at >= RECEIVED_RECLAIM_AFTER.ago &&
            record.payload_digest_was.present?
          idempotent = true
        else
          should_process = true
          record.assign_attributes(
            status: :received,
            processing_started_at: nil,
            processing_token: nil,
            next_retry_at: nil
          )
        end

        record.save! if record.changed?
        record
      end

      if mismatch
        return ServiceResult.failure(
          error: :webhook_event_payload_does_not_match_the_recorded_event,
          code: "event_payload_mismatch"
        )
      end

      ServiceResult.success(
        event: event,
        should_process: should_process,
        idempotent: idempotent,
        signature_bypassed: signature_bypassed
      )
    end

    def instrument_signature_bypass
      ActiveSupport::Notifications.instrument(
        "payments.webhook.signature_bypassed",
        provider: @provider,
        event_id: @event_id,
        event_type: @event_type
      )
    end

    def create_event_or_find_concurrent!(scope, normalized_payload, payload_digest)
      scope.create_or_find_by!(provider: @provider, event_id: @event_id) do |created|
        created.event_type = @event_type
        created.payload = normalized_payload
        created.payload_digest = payload_digest
        created.verified_at = Time.current
        created.status = :received
      end
    rescue ActiveRecord::RecordInvalid => error
      scope.find_by(provider: @provider, event_id: @event_id) || raise(error)
    end

    def same_digest?(left, right)
      left.bytesize == right.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(left, right)
    end

    def valid_identifier?(value)
      value.present? &&
        value.bytesize <= 255 &&
        value.match?(/\A[a-zA-Z0-9_.:-]+\z/)
    end
  end
end
