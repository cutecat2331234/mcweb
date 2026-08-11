# frozen_string_literal: true

module Operations
  class DurableEnqueueReducer
    State = Data.define(
      :generation,
      :last_event,
      :terminal,
      :status,
      :active_attempt,
      :active_lease_expires_at,
      :attempt_count,
      :retry_available_at
    ) do
      def terminal?
        terminal
      end

      def reopenable?
        last_event&.event_type == "dead_lettered"
      end

      def due?(now:, enqueue_stale_after:)
        return false if terminal?
        return active_lease_expires_at <= now if active_attempt
        return retry_available_at <= now if retry_available_at
        return false unless last_event

        last_event.occurred_at <= now - enqueue_stale_after
      end
    end

    class << self
      def call(intent)
        events = intent.events.order(:sequence).to_a
        return empty_state if events.empty?

        generation = events.last.generation
        generation_events = events.select { |event| event.generation == generation }
        last_event = generation_events.last
        terminal = last_event.event_type.in?(Operations::DurableEnqueueEvent::TERMINAL_EVENT_TYPES)
        attempts = intent.attempts.where(generation:).order(:attempt_number).to_a
        active_attempt = attempts.reverse.find do |attempt|
          generation_events.none? do |event|
            event.attempt_id == attempt.id && event.event_type.in?(%w[
              attempt_succeeded attempt_skipped attempt_failed
            ])
          end
        end
        renewal = if active_attempt
          generation_events.reverse.find do |event|
            event.attempt_id == active_attempt.id && event.event_type == "lease_renewed"
          end
        end
        retry_event = generation_events.reverse.find { |event| event.event_type == "retry_scheduled" }

        State.new(
          generation:,
          last_event:,
          terminal:,
          status: status_for(last_event, active_attempt),
          active_attempt:,
          active_lease_expires_at: renewal&.lease_expires_at || active_attempt&.lease_expires_at,
          attempt_count: attempts.length,
          retry_available_at: retry_event&.available_at
        )
      end

      private

      def empty_state
        State.new(
          generation: 1,
          last_event: nil,
          terminal: false,
          status: "unrecorded",
          active_attempt: nil,
          active_lease_expires_at: nil,
          attempt_count: 0,
          retry_available_at: nil
        )
      end

      def status_for(last_event, active_attempt)
        return "running" if active_attempt

        case last_event.event_type
        when "attempt_succeeded" then "succeeded"
        when "attempt_skipped" then "skipped"
        when "dead_lettered" then "dead_lettered"
        when "retry_scheduled" then "retrying"
        else "pending"
        end
      end
    end
  end
end
