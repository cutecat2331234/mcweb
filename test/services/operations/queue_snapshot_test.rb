# frozen_string_literal: true

require "test_helper"

module Operations
  class QueueSnapshotTest < ActiveSupport::TestCase
    Stats = Data.define(
      :enqueued,
      :retry_size,
      :scheduled_size,
      :dead_size,
      :failed,
      :processed
    )
    Queue = Data.define(:name, :size, :latency)

    test "reports privacy-safe Sidekiq capacity and queue latency" do
      result = QueueSnapshot.call(
        queue_adapter: :sidekiq,
        production: true,
        stats: Stats.new(
          enqueued: 18,
          retry_size: 2,
          scheduled_size: 4,
          dead_size: 0,
          failed: 7,
          processed: 120
        ),
        processes: [
          { "busy" => 3, "concurrency" => 10, "hostname" => "private-host" },
          { "busy" => 2, "concurrency" => 5, "identity" => "secret-process" }
        ],
        queues: [
          Queue.new(name: "mailers", size: 5, latency: 3.25),
          Queue.new(name: "default", size: 13, latency: 42.75)
        ],
        backlog_warning: 100,
        latency_warning_seconds: 60
      )

      assert result.success?
      snapshot = result.value
      assert_equal true, snapshot.fetch(:available)
      assert_equal "healthy", snapshot.fetch(:status)
      assert_equal 2, snapshot.fetch(:worker_count)
      assert_equal 5, snapshot.fetch(:busy_workers)
      assert_equal 15, snapshot.fetch(:concurrency)
      assert_equal 33.3, snapshot.fetch(:utilization_percent)
      assert_equal 42.75, snapshot.fetch(:oldest_wait_seconds)
      assert_equal %w[default mailers], snapshot.fetch(:queues).pluck(:name)
      refute_includes snapshot.to_json, "private-host"
      refute_includes snapshot.to_json, "secret-process"
    end

    test "warns on backlog or latency and fails readiness when production has no worker" do
      warning = QueueSnapshot.call(
        queue_adapter: :sidekiq,
        production: false,
        stats: empty_stats(enqueued: 100),
        processes: [],
        queues: [ Queue.new(name: "default", size: 100, latency: 61) ],
        backlog_warning: 100,
        latency_warning_seconds: 60
      )
      missing_worker = QueueSnapshot.call(
        queue_adapter: :sidekiq,
        production: true,
        stats: empty_stats,
        processes: [],
        queues: [],
        backlog_warning: 100,
        latency_warning_seconds: 60
      )

      assert_equal "warning", warning.value.fetch(:status)
      assert_equal "error", missing_worker.value.fetch(:status)
    end

    test "returns a recoverable unavailable snapshot without exception details" do
      broken_stats = Object.new
      broken_stats.define_singleton_method(:enqueued) do
        raise Redis::CannotConnectError, "redis://user:secret@example.test"
      end

      result = QueueSnapshot.call(
        queue_adapter: :sidekiq,
        stats: broken_stats,
        processes: [],
        queues: []
      )

      assert result.success?
      assert_equal false, result.value.fetch(:available)
      assert_equal "queue_snapshot_unavailable", result.value.fetch(:error_code)
      refute_includes result.value.to_json, "secret"
      refute_includes result.value.to_json, "Redis::"
    end

    test "describes non-Sidekiq adapters without contacting Redis" do
      result = QueueSnapshot.call(queue_adapter: :test)

      assert result.success?
      assert_equal "local", result.value.fetch(:status)
      assert_equal "test", result.value.fetch(:adapter)
      assert_empty result.value.fetch(:queues)
    end

    private

    def empty_stats(enqueued: 0)
      Stats.new(
        enqueued:,
        retry_size: 0,
        scheduled_size: 0,
        dead_size: 0,
        failed: 0,
        processed: 0
      )
    end
  end
end
