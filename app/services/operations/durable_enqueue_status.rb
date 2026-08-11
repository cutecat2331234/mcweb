# frozen_string_literal: true

module Operations
  class DurableEnqueueStatus
    class << self
      def call(intent)
        Operations::DurableEnqueueLedger.with_locked_intent(intent) do |state|
          entry = Operations::DurableEnqueueCatalog.entry(intent.handler_key)
          {
            public_id: intent.public_id,
            handler_key: intent.handler_key,
            queue_name: intent.queue_name,
            replay_contract: entry&.replay_contract,
            generation: state.generation,
            status: state.status,
            attempt_count: state.attempt_count,
            requested_at: intent.requested_at,
            last_event_at: state.last_event&.occurred_at,
            last_error_code: state.last_event&.error_code
          }
        end
      end
    end
  end
end
