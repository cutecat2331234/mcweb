# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class SystemSettingsControlsTest < ActionDispatch::IntegrationTest
    setup do
      admin = create_user(account_type: "owner")
      grant_permission(admin, "admin.access")
      grant_permission(admin, "system.settings.manage")
      grant_admin_module(admin, "system")
      sign_in_as(admin)

      SiteSetting.set("features.test.enabled", "true")
      SiteSetting.set("forum.auto_close_on_solved", "0")
      SiteSetting.set("forum.bump_cooldown_hours", "24")
      SiteSetting.set("forum.event_webhook_events", "topic.created,post.created")
      SiteSetting.set("forum.event_webhook_secret", "test-secret")
      SiteSetting.set("forum.online_peak_count", "10")
    end

    test "system settings expose boolean controls without changing stored encodings" do
      get admin_system_settings_path

      assert_response :success
      settings = inertia.props.deep_symbolize_keys.fetch(:settings).index_by { |setting| setting[:key] }

      assert_equal "boolean", settings.dig("features.test.enabled", :control)
      assert_equal "true", settings.dig("features.test.enabled", :enabled_value)
      assert_equal "false", settings.dig("features.test.enabled", :disabled_value)

      assert_equal "boolean", settings.dig("forum.auto_close_on_solved", :control)
      assert_equal "1", settings.dig("forum.auto_close_on_solved", :enabled_value)
      assert_equal "0", settings.dig("forum.auto_close_on_solved", :disabled_value)

      assert_equal "number", settings.dig("forum.bump_cooldown_hours", :control)
      assert_equal "forum", settings.dig("forum.bump_cooldown_hours", :category)
      assert_equal "textarea", settings.dig("forum.event_webhook_events", :control)
      assert settings.dig("forum.event_webhook_events", :wide)
      assert_equal "password", settings.dig("forum.event_webhook_secret", :control)
      assert_equal "readonly", settings.dig("forum.online_peak_count", :control)
    end
  end
end
