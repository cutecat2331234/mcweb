# frozen_string_literal: true

require "test_helper"

module Operations
  class RedisQueueHealthIntegrationTest < ActiveSupport::TestCase
    Stats = Data.define(
      :enqueued,
      :retry_size,
      :scheduled_size,
      :dead_size,
      :failed,
      :processed
    )

    test "readiness queue details include the privacy-safe durable recovery snapshot" do
      recovery = ServiceResult.success(
        dependency: "sidekiq_redis",
        status: "recovering",
        redis_available: true,
        ledger_available: true,
        database_fallback: false,
        pending_intents: 3,
        retrying_intents: 1,
        dead_lettered_intents: 0,
        last_recovery_result: "accepted"
      )
      checker = Operations::HealthChecker.new(
        queue_adapter: :sidekiq,
        production: false,
        sidekiq_stats: Stats.new(
          enqueued: 0,
          retry_size: 0,
          scheduled_size: 0,
          dead_size: 0,
          failed: 0,
          processed: 0
        ),
        sidekiq_processes: [],
        sidekiq_queues: []
      )

      Operations::RedisQueueRecoverySnapshot.stub(:call, recovery) do
        queue = checker.send(:check_queue)

        assert_equal "ok", queue.fetch(:status)
        assert_equal 3, queue.dig(:recovery, :pending_intents)
        assert_equal 1, queue.dig(:recovery, :retrying_intents)
        refute queue.fetch(:recovery).key?(:source_id)
        refute queue.fetch(:recovery).key?(:arguments)
      end
    end
  end
end
