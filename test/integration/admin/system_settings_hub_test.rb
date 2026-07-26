# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  module System
    class SystemSettingsHubTest < ActionDispatch::IntegrationTest
      setup do
        %w[general.site_name site.name site.url].each { |key| SiteSetting.unset(key) }
        @admin = create_user
        %w[
          admin.access
          minecraft.servers.manage
          system.jobs.read
          system.plugins.settings.manage
          system.settings.manage
        ].each { |permission| grant_permission(@admin, permission) }
        sign_in_as(@admin)
      end

      test "renders dedicated destinations and redacts sensitive setting values" do
        secret = "must-never-reach-system-settings-#{SecureRandom.hex(8)}"
        SiteSetting.set("test.system.webhook_secret", secret)

        get admin_system_settings_path

        assert_response :success
        assert_equal "Admin/System/Settings/Show", inertia.component

        props = inertia.props.deep_symbolize_keys
        assert_equal(
          { site_name: "McWeb", site_url: "" },
          props.fetch(:basicSettings)
        )
        sections = props.fetch(:sections)
        assert_equal %w[experience security extensions operations],
          sections.map { |section| section.fetch(:id) }

        entries = sections.flat_map { |section| section.fetch(:entries) }
        assert_equal %w[
          api_keys
          applications
          feature_toggles
          forum
          health_overview
          jobs
          minecraft
          plugin_settings
          rate_limits
          store
          webhook_subscriptions
        ], entries.map { |entry| entry.fetch(:id) }.sort
        assert entries.all? { |entry| entry.keys.sort == %i[id kind url] }

        settings = props.fetch(:settings)
        secret_setting = settings.find do |setting|
          setting.fetch(:key) == "test.system.webhook_secret"
        end
        assert_equal "", secret_setting.fetch(:value)
        assert secret_setting.fetch(:sensitive)
        assert secret_setting.fetch(:configured)
        refute settings.any? { |setting| %w[
          general.site_name
          site.name
          site.url
        ].include?(setting.fetch(:key)) }

        serialized = response.body
        refute_includes serialized, secret
        refute_includes serialized, "general.site_name"
        refute_includes serialized, "site.name"
        refute_includes serialized, "site.url"
      end

      test "updates only the typed basic settings whitelist and writes an exact audit" do
        SiteSetting.set("general.site_name", "Before")
        SiteSetting.set("site.name", "Before")
        SiteSetting.set("site.url", "https://before.example.com")
        forbidden_secret = "forbidden-#{SecureRandom.hex(8)}"
        original_forbidden_value = SiteSetting.get("store.order_webhook_secret")

        assert_difference -> { AuditLog.where(action: "admin.settings_updated").count }, 1 do
          patch admin_system_settings_path, params: {
            basic_settings: {
              site_name: "McWeb Community",
              site_url: "https://community.example.com/",
              webhook_secret: forbidden_secret
            },
            settings: {
              "store.order_webhook_secret" => forbidden_secret
            }
          }
        end

        assert_redirected_to admin_system_settings_path
        assert_equal "McWeb Community", SiteSetting.get("general.site_name")
        assert_equal "McWeb Community", SiteSetting.get("site.name")
        assert_equal "https://community.example.com", SiteSetting.get("site.url")
        assert_equal original_forbidden_value, SiteSetting.get("store.order_webhook_secret")

        audit = AuditLog.where(action: "admin.settings_updated").order(:id).last
        assert_equal %w[general.site_name site.name site.url],
          audit.metadata.fetch("keys")
        refute_includes audit.to_json, forbidden_secret
      end

      test "rejects invalid basic settings without partial writes or audit" do
        SiteSetting.set("general.site_name", "Stable")
        SiteSetting.set("site.name", "Stable")
        SiteSetting.set("site.url", "https://stable.example.com")

        assert_no_difference -> { AuditLog.where(action: "admin.settings_updated").count } do
          patch admin_system_settings_path, params: {
            basic_settings: {
              site_name: "",
              site_url: "https://user:password@example.com/private?token=secret"
            }
          }
        end

        assert_response :unprocessable_entity
        props = inertia.props.deep_symbolize_keys
        assert_equal "required", props.dig(:formErrors, :site_name)
        assert_equal "url_invalid", props.dig(:formErrors, :site_url)
        assert_equal "Stable", SiteSetting.get("general.site_name")
        assert_equal "Stable", SiteSetting.get("site.name")
        assert_equal "https://stable.example.com", SiteSetting.get("site.url")
      end

      test "hides destinations that require additional permissions" do
        delete identity_session_path
        limited_admin = create_user
        %w[admin.access system.settings.manage].each do |permission|
          grant_permission(limited_admin, permission)
        end
        sign_in_as(limited_admin)

        get admin_system_settings_path

        assert_response :success
        entries = inertia.props.deep_symbolize_keys.fetch(:sections)
          .flat_map { |section| section.fetch(:entries) }
        ids = entries.map { |entry| entry.fetch(:id) }
        assert_includes ids, "feature_toggles"
        assert_includes ids, "rate_limits"
        refute_includes ids, "minecraft"
        refute_includes ids, "plugin_settings"
        refute_includes ids, "jobs"
      end
    end
  end
end
