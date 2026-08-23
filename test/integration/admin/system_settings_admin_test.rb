# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class SystemSettingsAdminTest < ActionDispatch::IntegrationTest
    setup do
      @admin = create_user
      grant_permission(@admin, "admin.access")
      grant_permission(@admin, "system.settings.manage")
      grant_admin_module(@admin, "system")
      sign_in_as(@admin)

      SiteSetting.set("features.forum.enabled", "true")
      SiteSetting.set("features.store.enabled", "true")
      SiteSetting.set("forum.bump_cooldown_hours", "24")
      SiteSetting.set("forum.vapid_private_key", "server-only-secret")
      SiteSetting.set("store.flat_shipping_cents", "800")
      Mcweb::SettingsNamespaceRegistry.register(
        prefix: "owned_test.",
        owner: "test.dedicated_configuration"
      )
      SiteSetting.set("owned_test.policy_version", "7")
    end

    test "generic settings hide every dedicated core namespace" do
      get admin_system_settings_path

      assert_response :success
      settings = inertia.props.deep_symbolize_keys.fetch(:settings)
      keys = settings.map { |setting| setting.fetch(:key) }
      refute_includes keys, "features.forum.enabled"
      refute_includes keys, "forum.bump_cooldown_hours"
      refute_includes keys, "store.flat_shipping_cents"
      refute_includes keys, "owned_test.policy_version"
    end

    test "unknown keys inside core namespaces remain hidden in every locale" do
      @admin.update!(locale: "en")
      SiteSetting.set("forum.future_policy", "must-remain-dedicated")

      get admin_system_settings_path

      assert_response :success
      settings = inertia.props.deep_symbolize_keys.fetch(:settings)
      refute settings.any? { |setting| setting[:key] == "forum.future_policy" }
    end

    test "sensitive setting values are never returned and blank updates preserve them" do
      SiteSetting.set("test.system.webhook_secret", "server-only-secret")
      get admin_system_settings_path

      setting = inertia.props.deep_symbolize_keys.fetch(:settings)
        .find { |item| item[:key] == "test.system.webhook_secret" }

      assert_equal "", setting[:value]
      assert setting[:sensitive]
      assert setting[:configured]

      patch admin_system_settings_path, params: {
        settings: { "test.system.webhook_secret" => "" }
      }

      assert_redirected_to admin_system_settings_path
      assert_equal "server-only-secret", SiteSetting.get("test.system.webhook_secret")
    end

    test "generic settings cannot write dedicated feature flags" do
      patch admin_system_settings_path, params: {
        settings: {
          "features.forum.enabled" => "false",
          "features.store.enabled" => "false"
        }
      }

      assert_redirected_to admin_system_settings_path
      assert_equal "true", SiteSetting.get("features.forum.enabled")
      assert_equal "true", SiteSetting.get("features.store.enabled")
      assert_equal "此配置由专用配置页面管理，本次未作任何更改。", flash[:alert]
    end

    test "dedicated namespaces are hidden and rejected atomically without auditing values" do
      get admin_system_settings_path

      settings = inertia.props.deep_symbolize_keys.fetch(:settings)
      refute settings.any? { |item| item[:key] == "owned_test.policy_version" }

      submitted_secret = "must-not-audit-#{SecureRandom.hex(12)}"
      assert_difference -> { AuditLog.count }, 1 do
        patch admin_system_settings_path, params: {
          settings: {
            "owned_test.policy_version" => submitted_secret,
            "forum.bump_cooldown_hours" => "48"
          }
        }
      end

      assert_redirected_to admin_system_settings_path
      assert_equal "7", SiteSetting.get("owned_test.policy_version")
      assert_equal "24", SiteSetting.get("forum.bump_cooldown_hours")
      assert_equal "此配置由专用配置页面管理，本次未作任何更改。", flash[:alert]

      audit = AuditLog.order(:id).last
      assert_equal "admin.settings_protected_write_rejected", audit.action
      assert_equal [ "owned_test.policy_version" ], audit.metadata.fetch("keys")
      assert_equal "test.dedicated_configuration",
        audit.metadata.fetch("owners").fetch("owned_test.policy_version")
      refute_includes audit.to_json, submitted_secret
    end

    test "all known setting labels are complete in Chinese and English" do
      %w[zh-CN en].each do |locale|
        label_maps = I18n.with_locale(locale) do
          Admin::System::SettingsController::TRANSLATION_SCOPES.map do |scope|
            I18n.t("#{scope}.labels", default: {})
          end
        end
        missing = known_setting_keys.reject do |key|
          label_maps.any? { |labels| labels[key.to_sym].present? || labels[key].present? }
        end

        assert_empty missing, "Missing #{locale} labels: #{missing.join(', ')}"
      end
    end

    private

    def known_setting_keys
      source = Rails.root.join("app/javascript/lib/systemSettings.ts").read
      block = source.match(
        /export const KNOWN_SYSTEM_SETTING_KEYS = \[(.*?)\] as const/m
      )&.captures&.first

      assert block, "KNOWN_SYSTEM_SETTING_KEYS must remain declared"
      block.scan(/'([^']+)'/).flatten
    end

    def assert_setting_label(settings, key, expected)
      setting = settings.find { |item| item[:key] == key }
      assert setting, "Expected #{key} to be present"
      assert_equal expected, setting[:label]
      refute_equal key, setting[:label]
    end
  end
end
