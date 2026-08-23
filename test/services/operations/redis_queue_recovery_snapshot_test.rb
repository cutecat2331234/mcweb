# frozen_string_literal: true

require "test_helper"

module Operations
  class RedisQueueRecoverySnapshotTest < ActiveSupport::TestCase
    setup do
      Operations::DurableEnqueueEvent.connection.execute(<<~SQL)
        TRUNCATE TABLE
          operations_durable_enqueue_events,
          operations_durable_enqueue_attempts,
          operations_durable_enqueue_intents
        RESTART IDENTITY CASCADE
      SQL
    end

    test "falls back to the PostgreSQL ledger while Redis queue metrics are unavailable" do
      intent = create_intent(dedupe_key: "snapshot:redis-unavailable")
      Operations::DurableEnqueueLedger.append!(
        intent:,
        event_type: "enqueue_requested",
        metadata: { trigger: "maintenance" }
      )
      failure = Operations::DurableEnqueueLedger.append!(
        intent:,
        event_type: "enqueue_failed",
        error_code: "enqueue_failed",
        metadata: { trigger: "maintenance" }
      )

      result = Operations::RedisQueueRecoverySnapshot.call(
        queue_snapshot: unavailable_queue,
        now: failure.occurred_at + 1.minute
      )

      assert_predicate result, :success?
      snapshot = result.value
      assert_equal "unavailable", snapshot.fetch(:status)
      assert_equal false, snapshot.fetch(:redis_available)
      assert_equal true, snapshot.fetch(:database_fallback)
      assert_equal true, snapshot.fetch(:ledger_available)
      assert_equal 1, snapshot.fetch(:pending_intents)
      assert_equal "failed", snapshot.fetch(:last_recovery_result)
      assert_equal "maintenance", snapshot.fetch(:last_recovery_trigger)
      assert_equal failure.occurred_at.iso8601, snapshot.fetch(:last_enqueue_failure_at)
      refute_includes snapshot.to_json, intent.dedupe_key
      refute_includes snapshot.to_json, intent.public_id
      refute snapshot.key?(:source_id)
    end

    test "reports a successful recovery handoff without claiming business completion" do
      intent = create_intent(dedupe_key: "snapshot:recovered")
      Operations::DurableEnqueueLedger.append!(
        intent:,
        event_type: "enqueue_requested",
        metadata: { trigger: "maintenance" }
      )
      handoff = Operations::DurableEnqueueLedger.append!(
        intent:,
        event_type: "enqueue_succeeded",
        metadata: { trigger: "maintenance" }
      )

      snapshot = Operations::RedisQueueRecoverySnapshot.call(
        queue_snapshot: healthy_queue,
        now: handoff.occurred_at
      ).value

      assert_equal "recovering", snapshot.fetch(:status)
      assert_equal true, snapshot.fetch(:redis_available)
      assert_equal false, snapshot.fetch(:database_fallback)
      assert_equal 1, snapshot.fetch(:pending_intents)
      assert_equal "accepted", snapshot.fetch(:last_recovery_result)
      assert_equal handoff.occurred_at.iso8601,
        snapshot.fetch(:last_recovery_handoff_at)
    end

    test "counts only each intent's latest terminal state" do
      pending = create_intent(dedupe_key: "snapshot:pending")
      dead = create_intent(dedupe_key: "snapshot:dead")
      Operations::DurableEnqueueLedger.append!(
        intent: dead,
        event_type: "dead_lettered",
        error_code: "attempts_exhausted"
      )

      snapshot = Operations::RedisQueueRecoverySnapshot.call(
        queue_snapshot: healthy_queue
      ).value

      assert_equal "warning", snapshot.fetch(:status)
      assert_equal 1, snapshot.fetch(:pending_intents)
      assert_equal 1, snapshot.fetch(:dead_lettered_intents)
      assert_equal pending.requested_at.iso8601,
        snapshot.fetch(:oldest_pending_at)
    end

    test "does not hide a Sidekiq worker error behind an empty durable ledger" do
      snapshot = Operations::RedisQueueRecoverySnapshot.call(
        queue_snapshot: healthy_queue.merge(status: "error")
      ).value

      assert_equal "error", snapshot.fetch(:status)
      assert_equal "error", snapshot.fetch(:queue_status)
    end

    private

    def create_intent(dedupe_key:)
      intent = nil
      ActiveRecord.stub(:after_all_transactions_commit, ->(&) { }) do
        Operations::DurableEnqueueIntent.transaction do
          intent = Operations::DurableEnqueue.record!(
            handler: "community.web_push",
            source_id: SecureRandom.random_number(1_000_000) + 1,
            dedupe_key:
          )
        end
      end
      intent
    end

    def healthy_queue
      {
        adapter: "sidekiq",
        available: true,
        status: "healthy"
      }
    end

    def unavailable_queue
      {
        adapter: "sidekiq",
        available: false,
        status: "unavailable"
      }
    end
  end
end
