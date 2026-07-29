# frozen_string_literal: true

require "test_helper"

module Operations
  module Metrics
    class TrendQueryTest < ActiveSupport::TestCase
      setup do
        MetricBucket.delete_all
      end

      test "returns bounded current trends and previous-period comparisons" do
        now = Time.zone.parse("2026-07-29 17:00:30")
        record(
          "request.duration_ms",
          values: [ 100, 300 ],
          dimensions: { surface: "admin", outcome: "success" },
          at: now - 30.minutes
        )
        record(
          "request.duration_ms",
          values: [ 100 ],
          dimensions: { surface: "admin", outcome: "success" },
          at: now - 90.minutes
        )
        record(
          "request.server_error",
          values: [ 1 ],
          dimensions: { surface: "admin" },
          at: now - 20.minutes
        )
        record(
          "job.execution.duration_ms",
          values: [ 50, 75 ],
          dimensions: { queue: "maintenance", outcome: "success" },
          at: now - 10.minutes
        )
        record(
          "job.failure",
          values: [ 1 ],
          dimensions: { queue: "maintenance" },
          at: now - 10.minutes
        )
        record("queue.enqueued", values: [ 12 ], at: now - 5.minutes)
        record(
          "queue.utilization_percent",
          values: [ 92 ],
          at: now - 5.minutes
        )

        sql_count = 0
        subscriber = lambda do |_name, _start, _finish, _id, payload|
          sql_count += 1 unless %w[SCHEMA TRANSACTION].include?(
            payload[:name].to_s.upcase
          )
        end
        result = ActiveSupport::Notifications.subscribed(
          subscriber,
          "sql.active_record"
        ) do
          TrendQuery.call(range: "1h", now:)
        end

        assert result.fetch(:available)
        assert_equal "1h", result.fetch(:range)
        assert_equal 2, result.dig(:summary, :request_count)
        assert_equal 200.0, result.dig(:summary, :request_average_ms)
        assert_equal 1, result.dig(:summary, :server_errors)
        assert_equal 50.0, result.dig(
          :summary,
          :request_error_rate_percent
        )
        assert_equal 2, result.dig(:summary, :job_count)
        assert_equal 1, result.dig(:summary, :job_failures)
        assert_equal 12.0, result.dig(:summary, :queue_enqueued)
        assert_equal 92.0, result.dig(
          :summary,
          :queue_utilization_percent
        )
        assert_equal 100.0, result.dig(
          :comparison,
          :request_count
        )
        assert result.fetch(:series).any?
        assert_operator result.fetch(:row_count), :<=, TrendQuery::MAX_ROWS
        assert_operator sql_count, :<=, 3
      end

      test "fails closed instead of returning a query over the row budget" do
        query = TrendQuery.new(range: "30d")
        query.stub(:load_rows, Array.new(TrendQuery::MAX_ROWS + 1)) do
          result = query.call

          assert_not result.fetch(:available)
          assert result.fetch(:truncated)
          assert_equal "query_budget_exceeded", result.fetch(:error_code)
          assert_empty result.fetch(:series)
        end
      end

      private

      def record(metric_name, values:, at:, dimensions: {})
        buffer = Buffer.new(
          writer: ->(entries) { MetricBucket.atomic_merge!(entries) },
          clock: -> { at }
        )
        values.each do |value|
          buffer.record(
            metric_name,
            value:,
            dimensions:,
            at:
          )
        end
        buffer.flush!(now: at)
      end
    end
  end
end
