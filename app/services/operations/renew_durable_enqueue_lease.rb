# frozen_string_literal: true

module Operations
  class RenewDurableEnqueueLease < ApplicationService
    def initialize(intent_id:, attempt_id:, generation:, lease_token:, now: Time.current)
      @intent_id = intent_id
      @attempt_id = attempt_id
      @generation = Integer(generation, exception: false)
      @lease_token = lease_token.to_s
      @now = now
    end

    def call
      intent = Operations::DurableEnqueueIntent.find_by(id: @intent_id)
      return skipped("intent_missing") unless intent

      outcome = Operations::DurableEnqueueLedger.with_locked_intent(intent) do |state|
        attempt = state.active_attempt
        next :lease_stale if state.terminal? || state.generation != @generation
        next :lease_stale unless attempt&.id == @attempt_id && attempt.lease_token == @lease_token
        entry = Operations::DurableEnqueueCatalog.entry(intent.handler_key)
        next :handler_missing unless entry
        unless intent.source_kind == entry.source_kind && intent.queue_name == entry.queue_name
          next :handler_contract_mismatch
        end
        next :lease_stale unless state.active_lease_expires_at > @now

        Operations::DurableEnqueueLedger.append_locked!(
          intent:,
          state:,
          event_type: "lease_renewed",
          generation: @generation,
          attempt:,
          metadata: { attempt_number: attempt.attempt_number },
          occurred_at: @now,
          lease_expires_at: @now + entry.lease_seconds
        )
        :renewed
      end

      case outcome
      when :renewed
        ServiceResult.success(renewed: true)
      when :handler_missing, :handler_contract_mismatch
        code = "durable_enqueue_#{outcome}"
        ServiceResult.failure(error: code, code:)
      else
        skipped("lease_stale")
      end
    end

    private

    def skipped(reason_code)
      ServiceResult.success(skipped: true, reason_code:)
    end
  end
end
