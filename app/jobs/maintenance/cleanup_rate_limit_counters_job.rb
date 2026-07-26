# frozen_string_literal: true

module Maintenance
  class CleanupRateLimitCountersJob < ApplicationJob
    queue_as :maintenance

    BATCH_SIZE = 1_000
    # Counters created before expires_at was introduced did not persist their
    # window length. The longest configurable abuse window is 30 days, while
    # every other current caller uses at most one hour, so one extra day keeps
    # the legacy fallback conservative.
    LEGACY_RETENTION_PERIOD =
      Administration::AbuseRateLimit::MAX_WINDOW_SECONDS.seconds + 1.day

    def perform
      now = Time.current

      delete_in_batches(RateLimitCounter.where("expires_at <= ?", now))
      delete_in_batches(
        RateLimitCounter
          .where(expires_at: nil)
          .where("window_start <= ?", now - LEGACY_RETENTION_PERIOD)
      )
    end

    private

    def delete_in_batches(scope)
      scope.in_batches(of: BATCH_SIZE).delete_all
    end
  end
end
