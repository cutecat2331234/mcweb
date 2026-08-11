# frozen_string_literal: true

module Operations
  class DurableEnqueueLedger
    class InvalidTransition < StandardError; end

    class << self
      def state(intent)
        Operations::DurableEnqueueReducer.call(intent)
      end

      def with_locked_intent(intent)
        intent.with_lock do
          intent.association(:events).reset
          intent.association(:attempts).reset
          yield state(intent)
        end
      end

      def append!(intent:, event_type:, generation: nil, **attributes)
        with_locked_intent(intent) do |current|
          append_locked!(
            intent:,
            state: current,
            event_type:,
            generation:,
            **attributes
          )
        end
      end

      def append_locked!(
        intent:,
        state:,
        event_type:,
        generation: nil,
        attempt: nil,
        error_code: nil,
        metadata: {},
        occurred_at: Time.current,
        available_at: nil,
        lease_expires_at: nil
      )
        normalized_type = event_type.to_s
        normalized_generation = generation || state.generation
        validate_generation!(state, normalized_type, normalized_generation)

        intent.events.create!(
          sequence: intent.events.maximum(:sequence).to_i + 1,
          generation: normalized_generation,
          attempt:,
          event_type: normalized_type,
          error_code: error_code&.to_s,
          metadata: safe_metadata(metadata),
          occurred_at:,
          available_at:,
          lease_expires_at:
        )
      end

      private

      def validate_generation!(state, event_type, generation)
        if event_type == "recorded"
          unless state.last_event.nil? && generation == 1
            raise InvalidTransition, "durable_enqueue_recorded_generation_invalid"
          end
        elsif event_type == "reopened"
          unless state.reopenable? && generation == state.generation + 1
            raise InvalidTransition, "durable_enqueue_reopen_invalid"
          end
        elsif state.last_event.nil? || generation != state.generation
          raise InvalidTransition, "durable_enqueue_generation_stale"
        end
      end

      def safe_metadata(metadata)
        value = metadata.to_h.deep_stringify_keys.slice(
          "actor_id",
          "attempt_number",
          "reason",
          "trigger"
        )
        if ActiveSupport::JSON.encode(value).bytesize > 4.kilobytes
          raise ArgumentError, "durable_enqueue_event_metadata_too_large"
        end
        value
      end
    end
  end
end
