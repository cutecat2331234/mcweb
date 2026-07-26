# frozen_string_literal: true

require "test_helper"

module Maintenance
  class CleanupRateLimitCountersJobTest < ActiveJob::TestCase
    test "deletes expired counters while preserving active counters" do
      travel_to Time.zone.parse("2026-07-26 12:00:00") do
        expired = create_counter(
          key: "expired",
          window_start: 2.hours.ago,
          expires_at: 1.hour.ago
        )
        active = create_counter(
          key: "active",
          window_start: 1.minute.ago,
          expires_at: 14.minutes.from_now
        )

        CleanupRateLimitCountersJob.perform_now

        refute RateLimitCounter.exists?(expired.id)
        assert RateLimitCounter.exists?(active.id)
      end
    end

    test "conservatively removes only stale legacy counters without expires_at" do
      travel_to Time.zone.parse("2026-07-26 12:00:00") do
        stale_legacy = create_counter(
          key: "stale-legacy",
          window_start: 32.days.ago,
          expires_at: nil
        )
        recent_legacy = create_counter(
          key: "recent-legacy",
          window_start: 30.days.ago,
          expires_at: nil
        )

        CleanupRateLimitCountersJob.perform_now

        refute RateLimitCounter.exists?(stale_legacy.id)
        assert RateLimitCounter.exists?(recent_legacy.id)
      end
    end

    test "rate limiter persists the exact counter expiry" do
      travel_to Time.zone.parse("2026-07-26 12:00:00") do
        Administration::RateLimiter.call(key: "exact-expiry", limit: 10, window: 15.minutes)

        counter = RateLimitCounter.find_by!(key: "exact-expiry")
        assert_equal 15.minutes.from_now, counter.expires_at
      end
    end

    test "schema provides cleanup and prefix-like indexes" do
      indexes = ActiveRecord::Base.connection.indexes(:rate_limit_counters).index_by(&:name)
      prefix_index = indexes.fetch("index_rate_limit_counters_on_key_pattern")

      assert indexes.key?("index_rate_limit_counters_on_expires_at")
      assert indexes.key?("index_rate_limit_counters_on_window_start")
      assert_equal :varchar_pattern_ops, prefix_index.opclasses
    end

    test "daily cleanup is registered on the maintenance queue" do
      schedule = YAML.safe_load_file(Rails.root.join("config/sidekiq_cron.yml"))
      cleanup = schedule.fetch("cleanup_rate_limit_counters")

      assert_equal "15 3 * * *", cleanup.fetch("cron")
      assert_equal "Maintenance::CleanupRateLimitCountersJob", cleanup.fetch("class")
      assert_equal "maintenance", cleanup.fetch("queue")
      assert_equal true, cleanup.fetch("active_job")
    end

    private

    def create_counter(key:, window_start:, expires_at:)
      RateLimitCounter.create!(
        key: key,
        count: 1,
        window_start: window_start,
        expires_at: expires_at
      )
    end
  end
end
