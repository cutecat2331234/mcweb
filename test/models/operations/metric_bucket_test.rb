# frozen_string_literal: true

require "test_helper"

module Operations
  class MetricBucketTest < ActiveSupport::TestCase
    test "atomic merge adds concurrent process batches without overwriting" do
      bucket_at = Time.zone.parse("2026-07-29 15:10:00")
      first = entry(
        bucket_at:,
        metric_name: "queue.enqueued",
        value: 2
      )
      second = entry(
        bucket_at:,
        metric_name: "queue.enqueued",
        value: 5
      )
      ready = Queue.new
      gate = Queue.new
      errors = Queue.new
      threads = [ first, second ].map do |sample|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            gate.pop
            MetricBucket.atomic_merge!([ sample ])
          rescue StandardError => error
            errors << error
          end
        end
      end
      2.times { ready.pop }
      2.times { gate << true }
      threads.each(&:join)
      raise errors.pop unless errors.empty?

      row = MetricBucket.find_by!(
        bucket_at:,
        metric_name: "queue.enqueued",
        dimensions_key: first.fetch(:dimensions_key)
      )
      assert_equal 2, row.sample_count
      assert_equal 7.to_d, row.value_sum
      assert_equal 2.to_d, row.value_min
      assert_equal 5.to_d, row.value_max
    ensure
      MetricBucket.where(
        bucket_at:,
        metric_name: "queue.enqueued"
      ).delete_all if bucket_at
    end

    test "catalog persists only closed low-cardinality dimensions" do
      normalized = Metrics::Catalog.normalize(
        "payments.webhook.processed",
        value: 1,
        dimensions: {
          provider: "private-provider-user-42@example.com",
          outcome: "processed",
          user_id: 42,
          url: "https://token@example.com/private",
          sql: "SELECT secret FROM users",
          authorization: "Bearer top-secret"
        }
      )

      assert_equal(
        { "outcome" => "processed", "provider" => "other" },
        normalized.dimensions
      )
      serialized = normalized.dimensions.to_json
      refute_includes serialized, "example.com"
      refute_includes serialized, "secret"
      refute_includes serialized, "user_id"
      assert_match(/\A[0-9a-f]{64}\z/, normalized.dimensions_key)
    end

    private

    def entry(bucket_at:, metric_name:, value:)
      normalized = Metrics::Catalog.normalize(
        metric_name,
        value:,
        dimensions: {}
      )
      {
        bucket_at:,
        metric_name: normalized.metric_name,
        dimensions: normalized.dimensions,
        dimensions_key: normalized.dimensions_key,
        sample_count: 1,
        value_sum: normalized.value,
        value_min: normalized.value,
        value_max: normalized.value
      }
    end
  end
end
