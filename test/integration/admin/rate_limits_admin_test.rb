# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  module System
    class RateLimitsAdminTest < ActionDispatch::IntegrationTest
      setup do
        @admin = create_user
        grant_permission(@admin, "admin.access")
        grant_permission(@admin, "system.settings.manage")
        sign_in_as(@admin)
        RateLimitCounter.delete_all
      end

      test "authorized admin sees aggregate metrics without counter identifiers" do
        SiteSetting.set("security.rate_limits.login.account_limit", "1")
        identifier = "never-render-this-account@example.com"
        assert Administration::AbuseRateLimit.call(action: :login, account: identifier).success?
        assert Administration::AbuseRateLimit.call(action: :login, account: identifier).rate_limited?

        get admin_system_rate_limits_path

        assert_response :success
        assert_equal "no-store", response.headers["Cache-Control"]
        assert_equal "Admin/System/RateLimits/Show", inertia.component

        props = inertia.props.deep_symbolize_keys
        row = props[:rows].find do |entry|
          entry[:action] == "login" && entry[:dimension] == "account"
        end
        assert_equal 1, row[:active_counters]
        assert_equal 1, row[:blocked_requests]
        assert props[:csrf_token].present?

        rendered = props.to_json
        refute_includes rendered, identifier
        refute_includes rendered, Digest::SHA256.hexdigest(identifier)
        refute_includes rendered, "abuse:login:account:"
        refute_includes rendered, '"key"'
      end

      test "authorized admin updates validated policies with a stateful audit" do
        policies = effective_policies
        policies["login"]["account"]["limit"] = 42
        policies["login"]["account"]["window_seconds"] = 600

        assert_difference -> { AuditLog.where(action: "admin.rate_limit_settings_updated").count }, 1 do
          patch admin_system_rate_limits_path, params: { policies: policies }
        end

        assert_redirected_to admin_system_rate_limits_path
        assert_equal "42", SiteSetting.get("security.rate_limits.login.account_limit")
        assert_equal "600", SiteSetting.get("security.rate_limits.login.account_window_seconds")

        audit = AuditLog.where(action: "admin.rate_limit_settings_updated").order(:id).last
        assert_equal @admin.id, audit.actor_id
        assert_includes audit.metadata.fetch("changed_paths"), "login.account.limit"
        assert_equal 10, audit.before_state.fetch("login.account.limit")
        assert_equal 42, audit.after_state.fetch("login.account.limit")
      end

      test "invalid values return field errors and do not partially update or audit" do
        policies = effective_policies
        policies["login"]["account"]["limit"] = -1
        policies["search"]["ip"]["window_seconds"] = 0

        assert_no_difference -> { AuditLog.where(action: "admin.rate_limit_settings_updated").count } do
          patch admin_system_rate_limits_path, params: { policies: policies }
        end

        assert_response :unprocessable_entity
        assert_nil SiteSetting.get("security.rate_limits.login.account_limit")
        assert_nil SiteSetting.get("security.rate_limits.search.ip_window_seconds")

        props = inertia.props.deep_symbolize_keys
        assert_includes props[:formErrors], :"policies.login.account.limit"
        assert_includes props[:formErrors], :"policies.search.ip.window_seconds"
      end

      test "admin access without settings permission cannot read or change rate limits" do
        delete identity_session_path
        limited_admin = create_user
        grant_permission(limited_admin, "admin.access")
        sign_in_as(limited_admin)

        get admin_system_rate_limits_path
        assert_response :redirect
        assert_not_equal 200, response.status

        assert_no_changes -> { SiteSetting.get("security.rate_limits.login.account_limit") } do
          patch admin_system_rate_limits_path, params: { policies: effective_policies }
        end
        assert_response :redirect
        assert_not_equal 200, response.status
      end

      private

      def effective_policies
        Administration::AbuseRateLimit.policy_rows.each_with_object({}) do |policy, result|
          action = policy.fetch(:action).to_s
          dimension = policy.fetch(:dimension).to_s
          result[action] ||= {}
          result[action][dimension] = {
            limit: policy.fetch(:limit),
            window_seconds: policy.fetch(:window_seconds)
          }
        end
      end
    end
  end
end
