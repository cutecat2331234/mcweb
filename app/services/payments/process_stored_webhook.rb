# frozen_string_literal: true

module Payments
  class ProcessStoredWebhook < ApplicationService
    MAX_ATTEMPTS_PER_CYCLE = 5
    RETRY_DELAYS = [ 1.minute, 5.minutes, 15.minutes, 1.hour ].freeze
    RETRYABLE_ERROR_CODES = %w[
      payment_not_found
      provider_unavailable
      processing_error
      database_unavailable
      lock_timeout
    ].freeze

    Claim = Data.define(:event, :token, :attempt_number)

    def initialize(event:, source: "delivery", actor_id: nil)
      @event = event
      @source = source.to_s
      @actor_id = actor_id
    end

    def call
      claim = claim_event!
      return claim if claim.is_a?(ServiceResult)

      result = Payments::Provider.for(claim.event.provider).process_webhook_event(claim.event)
      finish_claim!(claim, result)
    rescue Payments::Provider::UnknownProviderError
      finish_exception_claim!(claim, code: "unknown_provider", retryable: false)
    rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionTimeoutError
      finish_exception_claim!(claim, code: "database_unavailable", retryable: true)
    rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked
      finish_exception_claim!(claim, code: "lock_timeout", retryable: true)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: {
        payment_webhook_event_id: @event.id,
        payment_webhook_provider: @event.provider
      })
      finish_exception_claim!(claim, code: "processing_error", retryable: true)
    end

    private

    def claim_event!
      token = SecureRandom.uuid
      attempt_number = nil
      blocked_result = nil

      event = Payments::WebhookEvent.transaction do
        record = Payments::WebhookEvent.lock.find(@event.id)

        unless record.verified_payload?
          quarantine_integrity_failure!(record)
          blocked_result = ServiceResult.failure(
            error: "Stored webhook payload failed integrity verification.",
            code: "payload_integrity_failure"
          )
          next record
        end

        if record.processed?
          blocked_result = ServiceResult.success(event: record, idempotent: true)
          next record
        end

        if record.dead_letter? && @source != "manual"
          blocked_result = ServiceResult.success(event: record, idempotent: true)
          next record
        end

        if record.processing? && !record.processing_stale?
          blocked_result = ServiceResult.success(event: record, idempotent: true, busy: true)
          next record
        end

        attempt_number = record.retry_count + 1
        record.update!(
          status: :processing,
          attempt_count: record.attempt_count + 1,
          retry_count: attempt_number,
          last_attempted_at: Time.current,
          processing_started_at: Time.current,
          processing_token: token,
          next_retry_at: nil,
          processed_at: nil,
          error_message: nil,
          last_error_code: nil
        )
        record
      end

      return blocked_result if blocked_result

      Claim.new(event, token, attempt_number)
    end

    def finish_claim!(claim, result)
      if result.success?
        finalize_success!(claim, result)
      else
        code = normalized_error_code(result.code)
        finalize_failure!(
          claim,
          code: code,
          retryable: RETRYABLE_ERROR_CODES.include?(code)
        )
      end
    end

    def finish_exception_claim!(claim, code:, retryable:)
      return ServiceResult.failure(error: "Webhook processing failed.", code: code) unless claim.is_a?(Claim)

      finalize_failure!(claim, code: code, retryable: retryable)
    end

    def finalize_success!(claim, provider_result)
      finalized = with_owned_claim(claim) do |record|
        record.update!(
          status: :processed,
          processed_at: Time.current,
          processing_started_at: nil,
          processing_token: nil,
          next_retry_at: nil,
          dead_lettered_at: nil,
          error_message: nil,
          last_error_code: nil
        )
      end

      instrument(finalized, outcome: "processed")
      audit_manual_result(finalized, outcome: "processed")
      ServiceResult.success(
        provider_result_value(provider_result).merge(
          event: finalized,
          idempotent: !finalized
        )
      )
    end

    def finalize_failure!(claim, code:, retryable:)
      dead_lettered = !retryable || claim.attempt_number >= MAX_ATTEMPTS_PER_CYCLE
      retry_at = Time.current + retry_delay(claim.attempt_number) unless dead_lettered

      finalized = with_owned_claim(claim) do |record|
        record.update!(
          status: dead_lettered ? :dead_letter : :failed,
          processed_at: dead_lettered ? Time.current : nil,
          processing_started_at: nil,
          processing_token: nil,
          next_retry_at: retry_at,
          dead_lettered_at: dead_lettered ? Time.current : nil,
          error_message: generic_error_message(code),
          last_error_code: code
        )
      end

      outcome = dead_lettered ? "dead_letter" : "retry_scheduled"
      instrument(finalized, outcome: outcome, error_code: code)
      audit_manual_result(finalized, outcome: outcome, error_code: code)
      log_failure(finalized, outcome: outcome, error_code: code)

      ServiceResult.failure(
        error: generic_error_message(code),
        code: code,
        value: {
          event: finalized,
          retry_scheduled: finalized&.failed? || false,
          dead_lettered: finalized&.dead_letter? || false
        }
      )
    end

    def with_owned_claim(claim)
      finalized = nil

      Payments::WebhookEvent.transaction do
        record = Payments::WebhookEvent.lock.find(claim.event.id)
        next unless record.processing? && secure_token_match?(record.processing_token, claim.token)

        yield record
        finalized = record
      end

      finalized
    end

    def quarantine_integrity_failure!(record)
      record.update!(
        status: :dead_letter,
        processed_at: Time.current,
        dead_lettered_at: Time.current,
        processing_started_at: nil,
        processing_token: nil,
        next_retry_at: nil,
        error_message: generic_error_message("payload_integrity_failure"),
        last_error_code: "payload_integrity_failure"
      )
    end

    def secure_token_match?(left, right)
      left.present? &&
        right.present? &&
        left.bytesize == right.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(left, right)
    end

    def normalized_error_code(code)
      value = code.to_s
      return "processing_failed" unless value.match?(/\A[a-z0-9_]{1,64}\z/)

      value
    end

    def retry_delay(attempt_number)
      RETRY_DELAYS.fetch(attempt_number - 1, RETRY_DELAYS.last)
    end

    def provider_result_value(result)
      return result.value if result.value.is_a?(Hash)
      return {} if result.value.nil?

      { result: result.value }
    end

    def generic_error_message(code)
      case code
      when "payment_not_found"
        "Payment dependency is not available yet."
      when "provider_unavailable"
        "Payment provider configuration is unavailable."
      when "payload_integrity_failure"
        "Stored webhook payload failed integrity verification."
      else
        "Webhook processing failed."
      end
    end

    def instrument(event, outcome:, error_code: nil)
      return unless event

      ActiveSupport::Notifications.instrument(
        "payments.webhook.processed",
        event_id: event.id,
        provider: event.provider,
        outcome: outcome,
        attempt_count: event.attempt_count,
        retry_count: event.retry_count,
        error_code: error_code
      )
    end

    def audit_manual_result(event, outcome:, error_code: nil)
      return unless @source == "manual" && @actor_id.present? && event

      Administration::AuditLogger.call(
        actor: User.find_by(id: @actor_id),
        action: "admin.payment_webhook_replay_processed",
        resource: event,
        metadata: {
          outcome: outcome,
          provider: event.provider,
          attempt_count: event.attempt_count,
          retry_count: event.retry_count,
          error_code: error_code
        }.compact
      )
    end

    def log_failure(event, outcome:, error_code:)
      return unless event

      Rails.logger.warn(
        "[Payments::Webhook] event=#{event.id} provider=#{event.provider} " \
        "outcome=#{outcome} attempt=#{event.attempt_count} code=#{error_code}"
      )
    end
  end
end
