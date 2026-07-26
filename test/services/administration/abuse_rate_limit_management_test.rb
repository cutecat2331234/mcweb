# frozen_string_literal: true

require "test_helper"

module Administration
  class AbuseRateLimitManagementTest < ActiveSupport::TestCase
    test "updates all validated settings atomically and reports changed state" do
      policies = effective_policies
      policies["login"]["account"]["limit"] = 12
      policies["login"]["account"]["window_seconds"] = 321

      result = Administration::UpdateAbuseRateLimitPolicies.call(policies: policies)

      assert result.success?
      assert_equal "12", SiteSetting.get("security.rate_limits.login.account_limit")
      assert_equal "321", SiteSetting.get("security.rate_limits.login.account_window_seconds")
      assert_includes result.value[:changed_paths], "login.account.limit"
      assert_equal 10, result.value[:before_state]["login.account.limit"]
      assert_equal 12, result.value[:after_state]["login.account.limit"]
    end

    test "rejects out-of-range and non-integer values without partial writes" do
      policies = effective_policies
      policies["login"]["account"]["limit"] = "12.5"
      policies["search"]["ip"]["window_seconds"] = AbuseRateLimit::MAX_WINDOW_SECONDS + 1
      original_search_window = SiteSetting.get("security.rate_limits.search.ip_window_seconds")

      result = Administration::UpdateAbuseRateLimitPolicies.call(policies: policies)

      assert result.failure?
      assert_includes result.errors, "policies.login.account.limit"
      assert_includes result.errors, "policies.search.ip.window_seconds"
      assert_nil SiteSetting.get("security.rate_limits.login.account_limit")
      if original_search_window.nil?
        assert_nil SiteSetting.get("security.rate_limits.search.ip_window_seconds")
      else
        assert_equal original_search_window, SiteSetting.get("security.rate_limits.search.ip_window_seconds")
      end
    end

    test "metrics aggregate only active policy buckets without serializing private keys" do
      SiteSetting.set("security.rate_limits.login.account_limit", "1")
      private_identifier = "private-user@example.com"

      assert AbuseRateLimit.call(action: :login, account: private_identifier).success?
      assert AbuseRateLimit.call(action: :login, account: private_identifier).rate_limited?

      result = AbuseRateLimitMetrics.call
      row = result.value[:rows].find do |entry|
        entry[:action] == "login" && entry[:dimension] == "account"
      end

      assert_equal 1, row[:active_counters]
      assert_equal 1, row[:blocked_requests]
      assert row[:last_blocked_at].present?

      serialized = result.value.to_json
      digest = Digest::SHA256.hexdigest(private_identifier)
      refute_includes serialized, private_identifier
      refute_includes serialized, digest
      refute_includes serialized, "abuse:login:account:"
      refute_includes serialized, '"key"'
    end

    test "expired buckets are excluded from operational aggregates" do
      RateLimitCounter.create!(
        key: "abuse:login:account:private-digest",
        count: 10,
        blocked_count: 7,
        last_blocked_at: 16.minutes.ago,
        window_start: 16.minutes.ago
      )

      row = AbuseRateLimitMetrics.call.value[:rows].find do |entry|
        entry[:action] == "login" && entry[:dimension] == "account"
      end

      assert_equal 0, row[:active_counters]
      assert_equal 0, row[:blocked_requests]
      assert_nil row[:last_blocked_at]
    end

    private

    def effective_policies
      AbuseRateLimit.policy_rows.each_with_object({}) do |policy, result|
        action = policy.fetch(:action).to_s
        dimension = policy.fetch(:dimension).to_s
        result[action] ||= {}
        result[action][dimension] = {
          "limit" => policy.fetch(:limit),
          "window_seconds" => policy.fetch(:window_seconds)
        }
      end
    end
  end
end
