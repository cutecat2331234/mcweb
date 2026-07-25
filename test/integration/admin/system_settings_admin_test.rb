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
    end

    test "settings expose localized labels instead of raw keys" do
      get admin_system_settings_path

      assert_response :success
      settings = inertia.props.deep_symbolize_keys.fetch(:settings)

      assert_setting_label(settings, "features.forum.enabled", "社区功能")
      assert_setting_label(settings, "forum.bump_cooldown_hours", "主题顶起冷却（小时）")
      assert_setting_label(settings, "store.flat_shipping_cents", "固定运费（分）")
    end

    test "labels follow the active English locale" do
      @admin.update!(locale: "en")

      get admin_system_settings_path

      assert_response :success
      settings = inertia.props.deep_symbolize_keys.fetch(:settings)
      assert_setting_label(settings, "features.forum.enabled", "Community feature")
      assert_setting_label(settings, "forum.bump_cooldown_hours", "Topic bump cooldown (hours)")
    end

    test "sensitive setting values are never returned and blank updates preserve them" do
      get admin_system_settings_path

      setting = inertia.props.deep_symbolize_keys.fetch(:settings)
        .find { |item| item[:key] == "forum.vapid_private_key" }

      assert_equal "", setting[:value]
      assert setting[:sensitive]
      assert setting[:configured]

      patch admin_system_settings_path, params: {
        settings: { "forum.vapid_private_key" => "" }
      }

      assert_redirected_to admin_system_settings_path
      assert_equal "server-only-secret", SiteSetting.get("forum.vapid_private_key")
    end

    test "generic settings cannot disable both portal modules" do
      patch admin_system_settings_path, params: {
        settings: {
          "features.forum.enabled" => "false",
          "features.store.enabled" => "false"
        }
      }

      assert_redirected_to admin_system_settings_path
      assert_equal "true", SiteSetting.get("features.forum.enabled")
      assert_equal "true", SiteSetting.get("features.store.enabled")
      assert_equal "论坛和商城至少需要保留一个开启。", flash[:alert]
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
