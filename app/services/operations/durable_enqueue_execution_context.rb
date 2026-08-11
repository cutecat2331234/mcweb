# frozen_string_literal: true

module Operations
  class DurableEnqueueExecutionContext
    attr_reader :intent_public_id,
                :idempotency_key,
                :generation,
                :attempt_number,
                :replay_contract

    def initialize(intent:, attempt:, entry:)
      @intent_id = intent.id
      @attempt_id = attempt.id
      @lease_token = attempt.lease_token
      @intent_public_id = intent.public_id.freeze
      @idempotency_key = "operations-durable:#{intent.public_id}".freeze
      @generation = attempt.generation
      @attempt_number = attempt.attempt_number
      @replay_contract = entry.replay_contract.freeze
    end

    def heartbeat!(now: Time.current)
      Operations::RenewDurableEnqueueLease.call(
        intent_id: @intent_id,
        attempt_id: @attempt_id,
        generation:,
        lease_token: @lease_token,
        now:
      )
    end
  end
end
