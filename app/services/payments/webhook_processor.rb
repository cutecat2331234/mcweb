# frozen_string_literal: true

module Payments
  class WebhookProcessor < ApplicationService
    STALE_PROCESSING_AFTER = 5.minutes

    def initialize(provider:, event_id:, event_type:, payload:, signature:, headers: {})
      @provider = provider.to_s
      @event_id = event_id.to_s
      @event_type = event_type.to_s
      @payload = payload
      @signature = signature
      @headers = headers
    end

    def call
      event = claim_event!
      return event if event.is_a?(ServiceResult)

      adapter = Provider.for(@provider)
      payload_body = @payload.is_a?(String) ? @payload : @payload.to_json

      unless adapter.verify_webhook_signature(payload: payload_body, signature: @signature, headers: @headers)
        event.mark_failed!("Invalid webhook signature.")
        return ServiceResult.failure(error: "Invalid webhook signature.")
      end

      result = adapter.process_webhook_event(event)

      if result.success?
        event.update!(status: "processed", processed_at: Time.current, error_message: nil)
      else
        event.update!(status: "failed", error_message: result.error)
      end

      result
    rescue Provider::UnknownProviderError => e
      ServiceResult.failure(error: e.message)
    end

    private

    def claim_event!
      idempotent = false

      event = Payments::WebhookEvent.transaction do
        record = Payments::WebhookEvent.lock.find_or_create_by!(provider: @provider, event_id: @event_id) do |created|
          created.event_type = @event_type
          created.payload = normalize_payload
          created.status = "received"
        end

        if record.status == "processed"
          idempotent = true
          next record
        end

        if record.status == "processing" && record.updated_at >= STALE_PROCESSING_AFTER.ago
          idempotent = true
          next record
        end

        record.update!(
          status: "processing",
          event_type: @event_type,
          error_message: nil
        )
        record
      end

      return ServiceResult.success(event: event, idempotent: true) if idempotent

      event
    end

    def normalize_payload
      case @payload
      when String
        JSON.parse(@payload)
      when Hash
        @payload
      else
        @payload.as_json
      end
    rescue JSON::ParserError
      { raw: @payload.to_s }
    end
  end
end
