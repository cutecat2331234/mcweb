# frozen_string_literal: true

module Operations
  class DispatchDurableIntentJob < ApplicationJob
    def perform(intent_id, generation, trigger)
      intent = Operations::DurableEnqueueIntent.find_by(id: intent_id)
      return unless intent

      entry = Operations::DurableEnqueueCatalog.entry(intent.handler_key)
      unless entry
        dead_letter_unknown_handler(intent, generation)
        return
      end

      attempt = claim(intent, entry:, generation:, trigger:)
      return unless attempt

      result = execute_with_heartbeat(intent, attempt:, entry:)
      finish(intent, attempt:, result:)
    rescue Operations::DurableEnqueueCatalog::ExecutionError => error
      raise unless attempt && entry

      fail_attempt(intent, attempt:, entry:, error_code: normalize_error_code(error.code))
    rescue StandardError => error
      Rails.logger.error(
        "[operations.durable_enqueue] execution_failed intent=#{intent&.public_id} error=#{error.class}"
      )
      raise unless attempt && entry

      fail_attempt(intent, attempt:, entry:, error_code: "execution_failed")
    end

    private

    def claim(intent, entry:, generation:, trigger:)
      normalized_generation = Integer(generation, exception: false)
      return unless normalized_generation&.positive?
      return unless trigger.to_s.in?(Operations::DurableEnqueueAttempt::TRIGGERS)

      now = Time.current
      Operations::DurableEnqueueLedger.with_locked_intent(intent) do |state|
        next if state.terminal? || state.generation != normalized_generation

        if state.active_attempt
          next if state.active_lease_expires_at > now

          append_lease_expired_unless_recorded(intent, state, state.active_attempt, now:)
          intent.association(:events).reset
          intent.association(:attempts).reset
          state = Operations::DurableEnqueueLedger.state(intent)
        end

        next if state.retry_available_at && state.retry_available_at > now

        if state.attempt_count >= entry.max_attempts
          Operations::DurableEnqueueLedger.append_locked!(
            intent:,
            state:,
            event_type: "dead_lettered",
            generation: normalized_generation,
            error_code: "attempts_exhausted",
            occurred_at: now
          )
          next
        end

        attempt = intent.attempts.create!(
          attempt_number: intent.attempts.maximum(:attempt_number).to_i + 1,
          generation: normalized_generation,
          lease_token: SecureRandom.uuid,
          job_id: job_id,
          trigger: trigger.to_s,
          started_at: now,
          lease_expires_at: now + entry.lease_seconds
        )
        Operations::DurableEnqueueLedger.append_locked!(
          intent:,
          state:,
          event_type: "attempt_started",
          generation: normalized_generation,
          attempt:,
          metadata: {
            attempt_number: attempt.attempt_number,
            trigger: trigger.to_s
          },
          occurred_at: now
        )
        attempt
      end
    end

    def finish(intent, attempt:, result:)
      Operations::DurableEnqueueLedger.with_locked_intent(intent) do |state|
        next if state.generation != attempt.generation
        next if attempt_closed?(intent, attempt)
        next unless latest_attempt?(intent, attempt)

        event_type = result.status == "skipped" ? "attempt_skipped" : "attempt_succeeded"
        Operations::DurableEnqueueLedger.append_locked!(
          intent:,
          state:,
          event_type:,
          generation: attempt.generation,
          attempt:,
          error_code: result.error_code,
          metadata: result.metadata,
          occurred_at: Time.current
        )
      end
    end

    def execute_with_heartbeat(intent, attempt:, entry:)
      context = Operations::DurableEnqueueExecutionContext.new(intent:, attempt:, entry:)
      heartbeat = Operations::DurableEnqueueHeartbeat.new(
        context:,
        interval: entry.heartbeat_seconds
      ).start
      Operations::DurableEnqueueCatalog.execute(intent, context:)
    ensure
      heartbeat&.stop
    end

    def fail_attempt(intent, attempt:, entry:, error_code:)
      now = Time.current
      Operations::DurableEnqueueLedger.with_locked_intent(intent) do |state|
        next if state.generation != attempt.generation
        next if attempt_closed?(intent, attempt)
        next unless latest_attempt?(intent, attempt)

        Operations::DurableEnqueueLedger.append_locked!(
          intent:,
          state:,
          event_type: "attempt_failed",
          generation: attempt.generation,
          attempt:,
          error_code:,
          occurred_at: now
        )
        intent.association(:events).reset
        current = Operations::DurableEnqueueLedger.state(intent)
        if current.attempt_count >= entry.max_attempts
          Operations::DurableEnqueueLedger.append_locked!(
            intent:,
            state: current,
            event_type: "dead_lettered",
            generation: attempt.generation,
            error_code: "attempts_exhausted",
            occurred_at: now
          )
        else
          delay = entry.retry_delays.fetch(
            [ current.attempt_count - 1, entry.retry_delays.length - 1 ].min,
            1.minute.to_i
          )
          Operations::DurableEnqueueLedger.append_locked!(
            intent:,
            state: current,
            event_type: "retry_scheduled",
            generation: attempt.generation,
            error_code:,
            occurred_at: now,
            available_at: now + delay
          )
        end
      end
    end

    def dead_letter_unknown_handler(intent, generation)
      normalized_generation = Integer(generation, exception: false)
      return unless normalized_generation&.positive?

      Operations::DurableEnqueueLedger.with_locked_intent(intent) do |state|
        next if state.terminal? || state.generation != normalized_generation

        Operations::DurableEnqueueLedger.append_locked!(
          intent:,
          state:,
          event_type: "dead_lettered",
          generation: normalized_generation,
          error_code: "handler_unavailable"
        )
      end
    end

    def append_lease_expired_unless_recorded(intent, state, attempt, now:)
      recorded = intent.events
        .where(event_type: "lease_expired", generation: attempt.generation)
        .where("metadata ->> 'attempt_number' = ?", attempt.attempt_number.to_s)
        .exists?
      return if recorded

      Operations::DurableEnqueueLedger.append_locked!(
        intent:,
        state:,
        event_type: "lease_expired",
        generation: attempt.generation,
        attempt:,
        metadata: { attempt_number: attempt.attempt_number },
        occurred_at: now
      )
    end

    def attempt_closed?(intent, attempt)
      intent.events.where(
        attempt:,
        event_type: %w[attempt_succeeded attempt_skipped attempt_failed lease_expired]
      ).exists?
    end

    def latest_attempt?(intent, attempt)
      intent.attempts.where(generation: attempt.generation).maximum(:attempt_number) ==
        attempt.attempt_number
    end

    def normalize_error_code(value)
      code = value.to_s
      code.match?(/\A[a-z][a-z0-9_]*\z/) ? code.first(120) : "execution_failed"
    end
  end
end
