# frozen_string_literal: true

module Operations
  class RedisQueueRecoverySnapshot < ApplicationService
    RECOVERY_TRIGGERS = %w[maintenance manual].freeze
    RECOVERY_EVENT_TYPES = %w[enqueue_succeeded enqueue_failed].freeze

    def initialize(queue_snapshot: nil, now: Time.current)
      @queue_snapshot = queue_snapshot
      @now = now
    end

    def call
      queue = normalized_queue_snapshot
      ledger = ledger_snapshot
      sidekiq = queue.fetch(:adapter, "sidekiq") == "sidekiq"

      ServiceResult.success(
        dependency: "sidekiq_redis",
        status: status(queue:, ledger:),
        redis_available: sidekiq ? queue.fetch(:available, false) : nil,
        queue_status: queue.fetch(:status, "unavailable"),
        database_fallback: sidekiq &&
          !queue.fetch(:available, false) &&
          ledger.fetch(:ledger_available),
        generated_at: @now.iso8601,
        **ledger
      )
    end

    private

    def normalized_queue_snapshot
      source = @queue_snapshot || Operations::QueueSnapshot.call.value
      source.to_h.symbolize_keys
    rescue StandardError
      {
        available: false,
        status: "unavailable"
      }
    end

    def ledger_snapshot
      unless ActiveRecord::Base.connection.data_source_exists?(
        "operations_durable_enqueue_events"
      )
        return unavailable_ledger
      end

      latest = latest_events
      pending = latest.where.not(
        event_type: Operations::DurableEnqueueEvent::TERMINAL_EVENT_TYPES
      )
      latest_counts = latest.group(:event_type).count
      oldest_pending_at = Operations::DurableEnqueueIntent
        .where(id: pending.select(:intent_id))
        .minimum(:requested_at)
      recoveries = recovery_events
      recovery_times = recoveries.group(:event_type).maximum(:occurred_at)
      latest_recovery = recoveries.order(occurred_at: :desc, id: :desc).first

      {
        ledger_available: true,
        pending_intents: pending_count(latest_counts),
        running_intents: latest_counts.values_at("attempt_started", "lease_renewed").compact.sum,
        retrying_intents: latest_counts.fetch("retry_scheduled", 0),
        dead_lettered_intents: latest_counts.fetch("dead_lettered", 0),
        oldest_pending_at: oldest_pending_at&.iso8601,
        oldest_pending_seconds: age_in_seconds(oldest_pending_at),
        last_enqueue_failure_at: Operations::DurableEnqueueEvent
          .where(event_type: "enqueue_failed")
          .maximum(:occurred_at)&.iso8601,
        last_recovery_handoff_at: recovery_times["enqueue_succeeded"]&.iso8601,
        last_recovery_failure_at: recovery_times["enqueue_failed"]&.iso8601,
        last_recovery_result: recovery_result(latest_recovery),
        last_recovery_trigger: latest_recovery&.metadata&.fetch("trigger", nil)
      }
    rescue ActiveRecord::ActiveRecordError
      unavailable_ledger
    end

    def latest_events
      Operations::DurableEnqueueEvent.where(<<~SQL.squish)
        NOT EXISTS (
          SELECT 1
          FROM operations_durable_enqueue_events later
          WHERE later.intent_id = operations_durable_enqueue_events.intent_id
            AND later.sequence > operations_durable_enqueue_events.sequence
        )
      SQL
    end

    def recovery_events
      Operations::DurableEnqueueEvent
        .where(event_type: RECOVERY_EVENT_TYPES)
        .where("metadata ->> 'trigger' IN (?)", RECOVERY_TRIGGERS)
    end

    def recovery_result(event)
      case event&.event_type
      when "enqueue_succeeded" then "accepted"
      when "enqueue_failed" then "failed"
      else "none"
      end
    end

    def pending_count(counts)
      terminal = Operations::DurableEnqueueEvent::TERMINAL_EVENT_TYPES
      counts.sum do |event_type, count|
        terminal.include?(event_type) ? 0 : count
      end
    end

    def age_in_seconds(timestamp)
      return unless timestamp

      [ (@now - timestamp).to_i, 0 ].max
    end

    def status(queue:, ledger:)
      return "local" unless queue.fetch(:adapter, "sidekiq") == "sidekiq"
      return "unavailable" unless queue.fetch(:available, false)
      return "error" unless ledger.fetch(:ledger_available)
      return "error" if queue.fetch(:status, "unavailable") == "error"
      return "warning" if queue.fetch(:status, "unavailable") == "warning"
      return "warning" if ledger.fetch(:dead_lettered_intents).positive?
      return "recovering" if ledger.fetch(:pending_intents).positive?

      "healthy"
    end

    def unavailable_ledger
      {
        ledger_available: false,
        ledger_error_code: "durable_enqueue_snapshot_unavailable",
        pending_intents: 0,
        running_intents: 0,
        retrying_intents: 0,
        dead_lettered_intents: 0,
        oldest_pending_at: nil,
        oldest_pending_seconds: nil,
        last_enqueue_failure_at: nil,
        last_recovery_handoff_at: nil,
        last_recovery_failure_at: nil,
        last_recovery_result: "none",
        last_recovery_trigger: nil
      }
    end
  end
end
