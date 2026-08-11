# frozen_string_literal: true

module Operations
  class DurableEnqueueDispatcher < ApplicationService
    class EnqueueFailure < StandardError; end

    def initialize(intent_id:, generation:, trigger:, now: Time.current)
      @intent_id = intent_id
      @generation = Integer(generation, exception: false)
      @trigger = trigger.to_s
      @now = now
    end

    def call
      return failure("durable_enqueue_trigger_invalid") unless @trigger.in?(Operations::DurableEnqueueAttempt::TRIGGERS)

      intent = Operations::DurableEnqueueIntent.find_by(id: @intent_id)
      return ServiceResult.success(skipped: true, reason_code: "intent_missing") unless intent

      entry = Operations::DurableEnqueueCatalog.entry(intent.handler_key)
      return failure("durable_enqueue_generation_invalid") unless @generation&.positive?
      unless entry
        terminalize_handler_error(intent, "handler_unavailable")
        return failure("durable_enqueue_handler_unknown")
      end
      unless intent.source_kind == entry.source_kind && intent.queue_name == entry.queue_name
        terminalize_handler_error(intent, "handler_snapshot_mismatch")
        return failure("durable_enqueue_handler_snapshot_mismatch")
      end

      should_enqueue = Operations::DurableEnqueueLedger.with_locked_intent(intent) do |state|
        next false if state.terminal? || state.generation != @generation
        next false if fresh_enqueue_handoff?(state, entry)
        next false if state.active_attempt && state.active_lease_expires_at > @now

        immediately_expected =
          (@trigger == "after_commit" && state.last_event&.event_type == "recorded") ||
          (@trigger == "manual" && state.last_event&.event_type == "reopened")
        due = state.due?(
          now: @now,
          enqueue_stale_after: entry.enqueue_stale_seconds
        )
        next false unless immediately_expected || due

        Operations::DurableEnqueueLedger.append_locked!(
          intent:,
          state:,
          event_type: "enqueue_requested",
          generation: @generation,
          metadata: { trigger: @trigger },
          occurred_at: @now
        )
        true
      end
      return ServiceResult.success(skipped: true, reason_code: "stale_or_terminal") unless should_enqueue

      job = Operations::DispatchDurableIntentJob
        .set(queue: entry.queue_name)
        .perform_later(intent.id, @generation, @trigger)
      unless job&.successfully_enqueued?
        raise EnqueueFailure, "durable enqueue adapter rejected the job"
      end

      append_enqueue_event(intent, "enqueue_succeeded")
      ServiceResult.success(enqueued: true, intent_public_id: intent.public_id)
    rescue StandardError => error
      append_enqueue_event(intent, "enqueue_failed", error_code: "enqueue_failed") if intent
      Rails.logger.error(
        "[operations.durable_enqueue] enqueue_failed intent=#{intent&.public_id} error=#{error.class}"
      )
      failure("durable_enqueue_enqueue_failed")
    end

    private

    def fresh_enqueue_handoff?(state, entry)
      return false unless state.last_event&.event_type.in?(%w[enqueue_requested enqueue_succeeded])

      state.last_event.occurred_at > @now - entry.enqueue_stale_seconds
    end

    def terminalize_handler_error(intent, error_code)
      Operations::DurableEnqueueLedger.with_locked_intent(intent) do |state|
        next if state.terminal? || state.generation != @generation

        Operations::DurableEnqueueLedger.append_locked!(
          intent:,
          state:,
          event_type: "dead_lettered",
          generation: @generation,
          error_code:,
          occurred_at: @now
        )
      end
    end

    def append_enqueue_event(intent, event_type, error_code: nil)
      Operations::DurableEnqueueLedger.with_locked_intent(intent) do |state|
        next if state.terminal? || state.generation != @generation

        Operations::DurableEnqueueLedger.append_locked!(
          intent:,
          state:,
          event_type:,
          generation: @generation,
          error_code:,
          metadata: { trigger: @trigger },
          occurred_at: @now
        )
      end
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
