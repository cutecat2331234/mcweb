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

      renewed = Operations::DurableEnqueueLedger.with_locked_intent(intent) do |state|
        attempt = state.active_attempt
        next false if state.terminal? || state.generation != @generation
        next false unless attempt&.id == @attempt_id && attempt.lease_token == @lease_token
        entry = Operations::DurableEnqueueCatalog.entry(intent.handler_key)
        next false unless entry
        next false unless intent.source_kind == entry.source_kind && intent.queue_name == entry.queue_name
        next false unless state.active_lease_expires_at > @now

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
        true
      end

      renewed ? ServiceResult.success(renewed: true) : skipped("lease_stale")
    end

    private

    def skipped(reason_code)
      ServiceResult.success(skipped: true, reason_code:)
    end
  end
end
