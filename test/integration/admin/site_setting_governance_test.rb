# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class SiteSettingGovernanceTest < ActionDispatch::IntegrationTest
    setup do
      @admin = create_user
      grant_permission(@admin, "admin.access")
      grant_permission(@admin, "system.settings.manage")
      grant_permission(@admin, "minecraft.servers.manage")
      grant_admin_module(@admin, "system")
      grant_admin_module(@admin, "minecraft")
      sign_in_as(@admin)
    end

    test "forum settings redact configured secrets and blank means preserve" do
      secret = "forum-secret-#{SecureRandom.hex(12)}"
      SiteSetting.set("forum.event_webhook_secret", secret)

      get admin_forum_settings_path

      assert_response :success
      setting = inertia.props.deep_symbolize_keys.fetch(:settings).find do |item|
        item.fetch(:key) == "forum.event_webhook_secret"
      end
      assert_equal "", setting.fetch(:value)
      assert setting.fetch(:sensitive)
      assert setting.fetch(:configured)
      refute_includes response.body, secret

      patch admin_forum_settings_path, params: {
        settings: {
          "forum.event_webhook_secret" => "",
          "forum.digest_hour" => "9"
        }
      }
      assert_redirected_to admin_forum_settings_path
      assert_equal secret, SiteSetting.get("forum.event_webhook_secret")
    end

    test "store settings redact configured secrets and blank means preserve" do
      secret = "store-secret-#{SecureRandom.hex(12)}"
      SiteSetting.set("store.order_webhook_secret", secret)

      get admin_store_settings_path

      assert_response :success
      setting = inertia.props.deep_symbolize_keys.fetch(:settings).find do |item|
        item.fetch(:key) == "store.order_webhook_secret"
      end
      assert_equal "", setting.fetch(:value)
      assert setting.fetch(:sensitive)
      assert setting.fetch(:configured)
      refute_includes response.body, secret

      patch admin_store_settings_path, params: {
        settings: {
          "store.order_webhook_secret" => "",
          "store.compare_max_items" => "5"
        }
      }
      assert_redirected_to admin_store_settings_path
      assert_equal secret, SiteSetting.get("store.order_webhook_secret")
    end

    test "typed errors are localized without echoing the rejected value" do
      rejected = "not-an-integer-#{SecureRandom.hex(8)}"
      previous = SiteSetting.get("forum.digest_hour")

      patch admin_forum_settings_path, params: {
        settings: { "forum.digest_hour" => rejected }
      }

      assert_redirected_to admin_forum_settings_path
      assert_equal "配置 forum.digest_hour 必须是整数。", flash[:alert]
      assert_equal previous, SiteSetting.get("forum.digest_hour")
      refute_includes flash[:alert], rejected

      @admin.update!(locale: "en")
      patch admin_forum_settings_path, params: {
        settings: { "forum.digest_hour" => rejected }
      }
      assert_equal "The setting forum.digest_hour must be a whole number.", flash[:alert]
      refute_includes flash[:alert], rejected
    end

    test "generic form rejects unknown keys inside reserved namespaces atomically" do
      SiteSetting.set("forum.future_policy", "stable")
      SiteSetting.set("custom.extension.label", "before")

      patch admin_system_settings_path, params: {
        settings: {
          "forum.future_policy" => "forged",
          "custom.extension.label" => "after"
        }
      }

      assert_redirected_to admin_system_settings_path
      assert_equal "stable", SiteSetting.get("forum.future_policy")
      assert_equal "before", SiteSetting.get("custom.extension.label")
      audit = AuditLog.order(:id).last
      assert_equal "admin.settings_protected_write_rejected", audit.action
      assert_equal [ "forum.future_policy" ], audit.metadata.fetch("keys")
      refute_includes audit.to_json, "forged"
    end
  end
end
