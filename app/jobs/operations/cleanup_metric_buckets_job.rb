# frozen_string_literal: true

module Operations
  class CleanupMetricBucketsJob < ApplicationJob
    queue_as :maintenance

    DEFAULT_RETENTION_DAYS = 30
    MIN_RETENTION_DAYS = 7
    MAX_RETENTION_DAYS = 365
    BATCH_SIZE = 1_000
    MAX_BATCHES = 100

    def perform(now: Time.current)
      cutoff = now.to_time.utc - retention_days.days
      deleted = 0

      MAX_BATCHES.times do
        ids = MetricBucket
          .where("bucket_at < ?", cutoff)
          .order(:id)
          .limit(BATCH_SIZE)
          .pluck(:id)
        break if ids.empty?

        deleted += MetricBucket.where(id: ids).delete_all
      end
      deleted
    end

    private

    def retention_days
      parsed = Integer(
        ENV.fetch(
          "MCWEB_OPERATIONS_METRICS_RETENTION_DAYS",
          DEFAULT_RETENTION_DAYS.to_s
        ),
        exception: false
      )
      return DEFAULT_RETENTION_DAYS unless parsed&.between?(
        MIN_RETENTION_DAYS,
        MAX_RETENTION_DAYS
      )

      parsed
    end
  end
end
