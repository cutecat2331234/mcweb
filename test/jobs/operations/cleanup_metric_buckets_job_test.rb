# frozen_string_literal: true

require "test_helper"

module Operations
  class CleanupMetricBucketsJobTest < ActiveJob::TestCase
    setup do
      MetricBucket.delete_all
    end

    test "deletes expired buckets while retaining the active window" do
      now = Time.zone.parse("2026-07-29 18:00:00")
      old = create_bucket(now - 31.days)
      recent = create_bucket(now - 29.days)

      assert_equal 1, CleanupMetricBucketsJob.perform_now(now:)
      assert_not MetricBucket.exists?(old.id)
      assert MetricBucket.exists?(recent.id)
    end

    private

    def create_bucket(at)
      normalized = Metrics::Catalog.normalize(
        "queue.enqueued",
        value: 1,
        dimensions: {}
      )
      MetricBucket.create!(
        bucket_at: at.change(sec: 0, usec: 0),
        metric_name: normalized.metric_name,
        dimensions: normalized.dimensions,
        dimensions_key: normalized.dimensions_key,
        sample_count: 1,
        value_sum: 1,
        value_min: 1,
        value_max: 1
      )
    end
  end
end
