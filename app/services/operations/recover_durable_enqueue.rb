# frozen_string_literal: true

module Operations
  class RecoverDurableEnqueue < ApplicationService
    DEFAULT_LIMIT = 200
    MAX_LIMIT = 1_000
    KEYSET_BATCH_SIZE = 200
    PUBLIC_ID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

    def initialize(
      limit: DEFAULT_LIMIT,
      intent_public_ids: nil,
      trigger: "maintenance",
      actor: nil,
      reopen: false,
      reason: nil,
      now: Time.current
    )
      @limit = limit.to_i.clamp(1, MAX_LIMIT)
      @intent_public_ids = Array(intent_public_ids).map { |value| value.to_s.downcase }.uniq
      @trigger = trigger.to_s
      @actor = actor
      @reopen = reopen == true
      @reason = reason.to_s.strip
      @now = now
    end

    def call
      return failure("durable_enqueue_trigger_invalid") unless @trigger.in?(%w[maintenance manual])
      if @intent_public_ids.any? { |value| !value.match?(PUBLIC_ID_PATTERN) } ||
          @intent_public_ids.length > 200
        return failure("durable_enqueue_public_ids_invalid")
      end
      if @reopen && (
        @trigger != "manual" ||
        !@actor&.persisted? ||
        !@actor.permission?("system.jobs.manage") ||
        @reason.blank? ||
        @reason.length > 500
      )
        return failure("durable_enqueue_reopen_invalid")
      end
      return failure("durable_enqueue_public_ids_required") if @reopen && @intent_public_ids.empty?

      scanned = 0
      due = 0
      enqueued = 0
      failed = 0
      skipped = 0
      public_ids = []

      catch(:durable_enqueue_limit_reached) do
        each_candidate do |intent|
          scanned += 1
          generation = prepare(intent)
          unless generation
            skipped += 1
            next
          end

          due += 1
          result = Operations::DurableEnqueueDispatcher.call(
            intent_id: intent.id,
            generation:,
            trigger: @trigger,
            now: @now
          )
          if result.success? && !result.value.to_h[:skipped]
            enqueued += 1
            public_ids << intent.public_id
          elsif result.success?
            skipped += 1
          else
            failed += 1
          end
          throw :durable_enqueue_limit_reached if due >= @limit
        end
      end

      value = {
        scanned_count: scanned,
        candidate_count: due,
        enqueued_count: enqueued,
        failed_count: failed,
        skipped_count: skipped,
        partial: failed.positive? && enqueued.positive?,
        intent_public_ids: public_ids
      }
      if failed.positive? && enqueued.zero?
        ServiceResult.failure(
          error: "durable_enqueue_recovery_failed",
          code: "durable_enqueue_recovery_failed",
          value:
        )
      else
        ServiceResult.success(value)
      end
    rescue ActiveRecord::ActiveRecordError => error
      Rails.logger.error("[operations.durable_enqueue] recovery_failed error=#{error.class}")
      failure("durable_enqueue_recovery_failed")
    end

    private

    def each_candidate
      scope = Operations::DurableEnqueueIntent.order(:id)
      if @intent_public_ids.any?
        scope = scope.where(public_id: @intent_public_ids)
      else
        latest_terminal_ids = Operations::DurableEnqueueEvent
          .where(event_type: Operations::DurableEnqueueEvent::TERMINAL_EVENT_TYPES)
          .where(<<~SQL.squish)
            NOT EXISTS (
              SELECT 1
              FROM operations_durable_enqueue_events later
              WHERE later.intent_id = operations_durable_enqueue_events.intent_id
                AND later.sequence > operations_durable_enqueue_events.sequence
            )
          SQL
          .select(:intent_id)
        scope = scope.where.not(id: latest_terminal_ids)
      end

      cursor = 0
      loop do
        batch = scope.where("operations_durable_enqueue_intents.id > ?", cursor)
                     .limit(KEYSET_BATCH_SIZE)
                     .to_a
        break if batch.empty?

        batch.each { |intent| yield intent }
        cursor = batch.last.id
      end
    end

    def prepare(intent)
      Operations::DurableEnqueueLedger.with_locked_intent(intent) do |state|
        if @reopen
          next unless state.reopenable?

          generation = state.generation + 1
          Operations::DurableEnqueueLedger.append_locked!(
            intent:,
            state:,
            event_type: "reopened",
            generation:,
            metadata: {
              actor_id: @actor.id,
              reason: @reason
            },
            occurred_at: @now
          )
          audit_reopen(intent, generation:)
          next generation
        end

        next if state.terminal?
        entry = Operations::DurableEnqueueCatalog.entry(intent.handler_key)
        next state.generation unless entry
        next unless state.due?(
          now: @now,
          enqueue_stale_after: entry.enqueue_stale_seconds
        )

        append_lease_expired_unless_recorded(intent, state) if state.active_attempt
        state.generation
      end
    end

    def append_lease_expired_unless_recorded(intent, state)
      attempt = state.active_attempt
      recorded = intent.events
        .where(event_type: "lease_expired", generation: state.generation)
        .where("metadata ->> 'attempt_number' = ?", attempt.attempt_number.to_s)
        .exists?
      return if recorded

      Operations::DurableEnqueueLedger.append_locked!(
        intent:,
        state:,
        event_type: "lease_expired",
        generation: state.generation,
        metadata: { attempt_number: attempt.attempt_number },
        occurred_at: @now
      )
    end

    def audit_reopen(intent, generation:)
      Administration::AuditLogger.call(
        actor: @actor,
        action: "operations.durable_enqueue.reopened",
        resource: intent,
        metadata: {
          intent_public_id: intent.public_id,
          handler_key: intent.handler_key,
          generation:,
          reason: @reason
        }
      )
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
