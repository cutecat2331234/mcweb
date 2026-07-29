# frozen_string_literal: true

module Operations
  module Metrics
    class TrendQuery < ApplicationService
      MAX_ROWS = 5_000

      RANGE_OPTIONS = {
        "1h" => { duration: 1.hour, resolution: 5.minutes },
        "6h" => { duration: 6.hours, resolution: 15.minutes },
        "24h" => { duration: 24.hours, resolution: 1.hour },
        "7d" => { duration: 7.days, resolution: 6.hours },
        "30d" => { duration: 30.days, resolution: 1.day }
      }.freeze
      DEFAULT_RANGE = "24h"

      DEFAULT_THRESHOLDS = {
        request_average_ms: 1_000.0,
        request_error_rate_percent: 1.0,
        job_failure_rate_percent: 5.0,
        mail_failure_rate_percent: 5.0,
        queue_utilization_percent: 90.0,
        queue_backlog: QueueSnapshot::DEFAULT_BACKLOG_WARNING.to_f
      }.freeze

      def initialize(range: DEFAULT_RANGE, now: Time.current)
        @range = RANGE_OPTIONS.key?(range.to_s) ? range.to_s : DEFAULT_RANGE
        @now = now.to_time.utc
      end

      def call
        return unavailable("storage_unavailable") unless storage_available?

        option = RANGE_OPTIONS.fetch(@range)
        to = @now.change(sec: 0, usec: 0) + 1.minute
        from = to - option.fetch(:duration)
        previous_from = from - option.fetch(:duration)
        rows = load_rows(
          from: previous_from,
          to:,
          resolution: option.fetch(:resolution)
        )
        return unavailable("query_budget_exceeded", truncated: true) if rows.length > MAX_ROWS

        current_rows, previous_rows = rows.partition do |row|
          period_at(row) >= from
        end
        current = summarize(current_rows)
        previous = summarize(previous_rows)

        {
          available: true,
          error_code: nil,
          range: @range,
          ranges: RANGE_OPTIONS.keys,
          generated_at: @now.iso8601,
          from: from.iso8601,
          to: to.iso8601,
          resolution_seconds: option.fetch(:resolution).to_i,
          row_budget: MAX_ROWS,
          row_count: rows.length,
          truncated: false,
          thresholds: thresholds,
          summary: current,
          comparison: comparison(current, previous),
          checks: checks(current),
          series: build_series(current_rows)
        }
      rescue ActiveRecord::ActiveRecordError => error
        Rails.logger.warn(
          "[operations.metrics] trend query unavailable: #{error.class.name}"
        )
        unavailable("query_unavailable")
      end

      private

      def storage_available?
        ActiveRecord::Base.connection.data_source_exists?(
          "operations_metric_buckets"
        )
      rescue ActiveRecord::ActiveRecordError
        false
      end

      def load_rows(from:, to:, resolution:)
        interval = Integer(resolution.to_i)
        period_sql = MetricBucket.sanitize_sql_array(
          [
            "date_bin(CAST(? AS interval), bucket_at, CAST(? AS timestamp))",
            "#{interval} seconds",
            from
          ]
        )

        MetricBucket
          .within(from:, to:)
          .select(
            Arel.sql("#{period_sql} AS period_at"),
            :metric_name,
            :dimensions,
            Arel.sql("SUM(sample_count) AS sample_count"),
            Arel.sql("SUM(value_sum) AS value_sum"),
            Arel.sql("MIN(value_min) AS value_min"),
            Arel.sql("MAX(value_max) AS value_max")
          )
          .group(Arel.sql(period_sql), :metric_name, :dimensions)
          .order(Arel.sql("period_at ASC"), :metric_name)
          .limit(MAX_ROWS + 1)
          .to_a
      end

      def summarize(rows)
        totals = totals_by_metric(rows)
        request_count = count_for(totals, "request.duration_ms")
        server_errors = count_for(totals, "request.server_error")
        job_count = count_for(totals, "job.execution.duration_ms")
        job_failures = count_for(totals, "job.failure")
        mail_deliveries = count_for(totals, "mail.delivery.duration_ms")
        mail_failures = count_for(totals, "mail.failure")

        {
          request_count:,
          request_average_ms: average_for(
            totals,
            "request.duration_ms"
          ),
          request_max_ms: maximum_for(totals, "request.duration_ms"),
          server_errors:,
          request_error_rate_percent: rate(server_errors, request_count),
          slow_query_count: count_for(
            totals,
            "database.slow_query.duration_ms"
          ),
          slow_query_max_ms: maximum_for(
            totals,
            "database.slow_query.duration_ms"
          ),
          job_count:,
          job_average_ms: average_for(
            totals,
            "job.execution.duration_ms"
          ),
          job_failures:,
          job_failure_rate_percent: rate(job_failures, job_count),
          mail_deliveries:,
          mail_failures:,
          mail_failure_rate_percent: rate(mail_failures, mail_deliveries),
          payment_webhooks: count_for(
            totals,
            "payments.webhook.processed"
          ),
          payment_webhook_failures: subset_count(
            rows,
            "payments.webhook.processed",
            "outcome" => %w[retry_scheduled dead_letter]
          ),
          uploads: count_for(totals, "community.upload.event"),
          upload_failures: subset_count(
            rows,
            "community.upload.event",
            "event" => %w[quota_rejected cleanup_failed]
          ),
          scans: count_for(totals, "community.scan.event"),
          scan_failures: subset_count(
            rows,
            "community.scan.event",
            "outcome" => %w[infected error]
          ),
          queue_enqueued: latest_average(rows, "queue.enqueued"),
          queue_oldest_wait_seconds: latest_average(
            rows,
            "queue.oldest_wait_seconds"
          ),
          queue_utilization_percent: latest_average(
            rows,
            "queue.utilization_percent"
          ),
          queue_worker_count: latest_average(rows, "queue.worker_count")
        }
      end

      def totals_by_metric(rows)
        rows.each_with_object({}) do |row, totals|
          aggregate = totals[row.metric_name] ||= empty_aggregate
          merge_row!(aggregate, row)
        end
      end

      def empty_aggregate
        { count: 0, sum: 0.to_d, max: 0.to_d }
      end

      def merge_row!(aggregate, row)
        aggregate[:count] += row.sample_count.to_i
        aggregate[:sum] += row.value_sum.to_d
        aggregate[:max] = [
          aggregate.fetch(:max),
          row.value_max.to_d
        ].max
      end

      def count_for(totals, metric_name)
        totals.fetch(metric_name, empty_aggregate).fetch(:count)
      end

      def average_for(totals, metric_name)
        aggregate = totals.fetch(metric_name, empty_aggregate)
        count = aggregate.fetch(:count)
        return 0.0 if count.zero?

        (aggregate.fetch(:sum) / count).to_f.round(2)
      end

      def maximum_for(totals, metric_name)
        totals.fetch(metric_name, empty_aggregate).fetch(:max).to_f.round(2)
      end

      def subset_count(rows, metric_name, expected)
        rows.sum do |row|
          next 0 unless row.metric_name == metric_name

          dimensions = row.dimensions.to_h.stringify_keys
          matches = expected.all? do |key, values|
            Array(values).include?(dimensions[key])
          end
          matches ? row.sample_count.to_i : 0
        end
      end

      def latest_average(rows, metric_name)
        row = rows.reverse_each.find { |candidate| candidate.metric_name == metric_name }
        return 0.0 unless row

        count = row.sample_count.to_i
        return 0.0 if count.zero?

        (row.value_sum.to_d / count).to_f.round(2)
      end

      def build_series(rows)
        grouped = rows.group_by { |row| period_at(row) }
        grouped.keys.sort.map do |bucket_at|
          bucket_rows = grouped.fetch(bucket_at)
          totals = totals_by_metric(bucket_rows)
          request_count = count_for(totals, "request.duration_ms")

          {
            bucket_at: bucket_at.iso8601,
            request_count:,
            request_average_ms: average_for(
              totals,
              "request.duration_ms"
            ),
            server_errors: count_for(
              totals,
              "request.server_error"
            ),
            slow_queries: count_for(
              totals,
              "database.slow_query.duration_ms"
            ),
            job_count: count_for(
              totals,
              "job.execution.duration_ms"
            ),
            job_failures: count_for(totals, "job.failure"),
            queue_enqueued: latest_average(
              bucket_rows,
              "queue.enqueued"
            ),
            queue_utilization_percent: latest_average(
              bucket_rows,
              "queue.utilization_percent"
            )
          }
        end
      end

      def comparison(current, previous)
        %i[
          request_count request_average_ms server_errors slow_query_count
          job_count job_failures mail_deliveries mail_failures payment_webhooks
          uploads scans queue_enqueued queue_utilization_percent
        ].to_h do |key|
          old_value = previous.fetch(key).to_f
          delta =
            if old_value.zero?
              nil
            else
              (
                (current.fetch(key).to_f - old_value) /
                old_value *
                100
              ).round(1)
            end
          [ key, delta ]
        end
      end

      def checks(summary)
        [
          check(
            "requests",
            summary.fetch(:request_average_ms),
            thresholds.fetch(:request_average_ms),
            unit: "ms",
            critical_multiplier: 2
          ),
          check(
            "server_errors",
            summary.fetch(:request_error_rate_percent),
            thresholds.fetch(:request_error_rate_percent),
            unit: "percent",
            critical_multiplier: 5
          ),
          check(
            "jobs",
            summary.fetch(:job_failure_rate_percent),
            thresholds.fetch(:job_failure_rate_percent),
            unit: "percent",
            critical_multiplier: 3
          ),
          check(
            "mail",
            summary.fetch(:mail_failure_rate_percent),
            thresholds.fetch(:mail_failure_rate_percent),
            unit: "percent",
            critical_multiplier: 3
          ),
          check(
            "queue",
            summary.fetch(:queue_utilization_percent),
            thresholds.fetch(:queue_utilization_percent),
            unit: "percent",
            critical_multiplier: 1.1
          ),
          check(
            "backlog",
            summary.fetch(:queue_enqueued),
            thresholds.fetch(:queue_backlog),
            unit: "count",
            critical_multiplier: 2
          )
        ]
      end

      def check(key, value, threshold, unit:, critical_multiplier:)
        status =
          if value >= threshold * critical_multiplier
            "critical"
          elsif value >= threshold
            "warning"
          else
            "healthy"
          end
        {
          key:,
          status:,
          unit:,
          value: value.to_f.round(2),
          threshold: threshold.to_f.round(2),
          percent: threshold.zero? ?
            0.0 :
            (value.to_f / threshold).clamp(0, 1).round(4)
        }
      end

      def thresholds
        @thresholds ||= {
          request_average_ms: configured_threshold(
            "MCWEB_REQUEST_LATENCY_WARNING_MS",
            DEFAULT_THRESHOLDS.fetch(:request_average_ms),
            50..60_000
          ),
          request_error_rate_percent: configured_threshold(
            "MCWEB_REQUEST_ERROR_RATE_WARNING_PERCENT",
            DEFAULT_THRESHOLDS.fetch(:request_error_rate_percent),
            0.1..100
          ),
          job_failure_rate_percent: configured_threshold(
            "MCWEB_JOB_FAILURE_RATE_WARNING_PERCENT",
            DEFAULT_THRESHOLDS.fetch(:job_failure_rate_percent),
            0.1..100
          ),
          mail_failure_rate_percent: configured_threshold(
            "MCWEB_MAIL_FAILURE_RATE_WARNING_PERCENT",
            DEFAULT_THRESHOLDS.fetch(:mail_failure_rate_percent),
            0.1..100
          ),
          queue_utilization_percent: configured_threshold(
            "MCWEB_QUEUE_UTILIZATION_WARNING_PERCENT",
            DEFAULT_THRESHOLDS.fetch(:queue_utilization_percent),
            1..100
          ),
          queue_backlog: configured_threshold(
            "MCWEB_QUEUE_BACKLOG_WARNING",
            DEFAULT_THRESHOLDS.fetch(:queue_backlog),
            1..1_000_000
          )
        }.freeze
      end

      def configured_threshold(name, default, range)
        parsed = Float(ENV.fetch(name, default.to_s), exception: false)
        range.cover?(parsed) ? parsed : default
      end

      def rate(numerator, denominator)
        return 0.0 if denominator.zero?

        (numerator.to_f / denominator * 100).round(2)
      end

      def period_at(row)
        row.read_attribute("period_at").to_time.utc
      end

      def unavailable(error_code, truncated: false)
        {
          available: false,
          error_code:,
          range: @range,
          ranges: RANGE_OPTIONS.keys,
          generated_at: @now.iso8601,
          from: nil,
          to: nil,
          resolution_seconds: nil,
          row_budget: MAX_ROWS,
          row_count: 0,
          truncated:,
          thresholds: thresholds,
          summary: {},
          comparison: {},
          checks: [],
          series: []
        }
      end
    end
  end
end
