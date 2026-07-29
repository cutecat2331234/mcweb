# frozen_string_literal: true

require "test_helper"

module Operations
  class FlushMetricsJobTest < ActiveJob::TestCase
    setup do
      @previous_factory = FlushMetricsJob.queue_snapshot_factory
      Metrics.reset!
    end

    teardown do
      FlushMetricsJob.queue_snapshot_factory = @previous_factory
      Metrics.reset!
    end

    test "samples queue capacity and flushes the process-local buffer" do
      now = Time.zone.parse("2026-07-29 18:30:00")
      written = []
      Metrics.buffer = Metrics::Buffer.new(
        clock: -> { now },
        writer: ->(entries) { written.concat(entries) }
      )
      FlushMetricsJob.queue_snapshot_factory = -> {
        ServiceResult.success(
          available: true,
          enqueued: 12,
          oldest_wait_seconds: 3.5,
          utilization_percent: 75.0,
          worker_count: 2
        )
      }

      assert_equal 4, FlushMetricsJob.perform_now(now:)
      assert_equal(
        %w[
          queue.enqueued queue.oldest_wait_seconds
          queue.utilization_percent queue.worker_count
        ],
        written.map { |entry| entry.fetch(:metric_name) }.sort
      )
    end
  end
end
