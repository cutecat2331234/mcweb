# frozen_string_literal: true

module Administration
  # Builds privacy-preserving operational metrics for the public-entry rate
  # limits. Only server-defined policy coordinates are queried and serialized;
  # counter keys and their hashed account/IP identifiers never leave this
  # service.
  class AbuseRateLimitMetrics < ApplicationService
    def initialize(now: Time.current)
      @now = now
    end

    def call
      rows = Administration::AbuseRateLimit.policy_rows.map do |policy|
        serialize_policy(policy)
      end

      ServiceResult.success(
        rows: rows,
        summary: {
          configured_dimensions: rows.count { |row| row[:limit].positive? },
          active_counters: rows.sum { |row| row[:active_counters] },
          blocked_requests: rows.sum { |row| row[:blocked_requests] }
        }
      )
    end

    private

    def serialize_policy(policy)
      scope = active_scope(policy)

      {
        id: "#{policy.fetch(:action)}:#{policy.fetch(:dimension)}",
        action: policy.fetch(:action).to_s,
        dimension: policy.fetch(:dimension).to_s,
        limit: policy.fetch(:limit),
        window_seconds: policy.fetch(:window_seconds),
        active_counters: scope.count,
        blocked_requests: scope.sum(:blocked_count),
        last_blocked_at: scope.maximum(:last_blocked_at)
      }
    end

    def active_scope(policy)
      prefix = "abuse:#{policy.fetch(:action)}:#{policy.fetch(:dimension)}:"
      escaped_prefix = ActiveRecord::Base.sanitize_sql_like(prefix)

      RateLimitCounter
        .where("key LIKE ?", "#{escaped_prefix}%")
        .where("window_start > ?", @now - policy.fetch(:window_seconds).seconds)
    end
  end
end
