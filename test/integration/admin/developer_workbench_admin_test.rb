# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  module System
    class DeveloperWorkbenchAdminTest < ActionDispatch::IntegrationTest
      test "returns not found before authentication when Developer Mode is disabled" do
        with_developer_mode(enabled: false) do
          get admin_system_developer_workbench_path

          assert_response :not_found
        end
      end

      test "requires system settings permission when Developer Mode is enabled" do
        admin = create_user
        grant_permission(admin, "admin.access")
        sign_in_as(admin)

        with_developer_mode(enabled: true) do
          get admin_system_developer_workbench_path

          assert_redirected_to admin_root_path
        end
      end

      test "renders only a redacted read-only snapshot for an authorized admin" do
        secret_target = "workbench-secret-#{SecureRandom.hex(12)}@example.test"
        admin = create_user
        grant_permission(admin, "admin.access")
        grant_permission(admin, "system.settings.manage")
        sign_in_as(admin)

        with_developer_mode(
          enabled: true,
          auto_login_user: secret_target
        ) do
          get admin_system_developer_workbench_path

          assert_response :success
          assert_equal "Admin/System/DeveloperWorkbench/Show", inertia.component

          props = inertia.props.deep_symbolize_keys
          assert_equal "unrestricted", props.fetch(:profile)
          assert_equal true, props.fetch(:autoLoginConfigured)
          assert_equal false, props.fetch(:automaticRegistration)
          assert_equal admin_system_settings_path, props.fetch(:settingsUrl)
          assert_equal admin_system_jobs_path, props.fetch(:jobsUrl)
          assert_equal true, props.dig(
            :developer_mode,
            :workbench_access
          )

          assert_equal %i[integrations runtime security],
            props.fetch(:configuration).keys.sort
          assert_equal %i[mail webPush webhooks],
            props.fetch(:captures).keys.sort
          assert_equal true, props.fetch(:minecraft).key?(:recent)

          serialized = response.body
          refute_includes serialized, secret_target
          refute_includes serialized, Rails.root.to_s
          refute_includes serialized, '"payload"'
          refute_includes serialized, '"headers"'
          refute_includes serialized, '"auto_login_user"'
        end
      end

      private

      def with_developer_mode(enabled:, auto_login_user: nil)
        settings = Mcweb::DeveloperMode.parse(
          config: {
            developer_mode: {
              enabled: enabled,
              auto_login_user: auto_login_user
            }
          },
          environment: {}
        )
        previous_settings =
          Mcweb::DeveloperMode.instance_variable_get(:@settings)
        Mcweb::DeveloperMode.instance_variable_set(:@settings, settings)
        yield
      ensure
        Mcweb::DeveloperMode.instance_variable_set(
          :@settings,
          previous_settings
        )
      end
    end
  end
end
