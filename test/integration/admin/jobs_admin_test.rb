# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  module System
    class JobsAdminTest < ActionDispatch::IntegrationTest
      setup do
        @admin = create_user
        grant_permission(@admin, "admin.access")
        grant_permission(@admin, "system.jobs.read")
        grant_admin_module(@admin, "system")
        sign_in_as(@admin)
      end

      test "standard mode reports active automatic scheduling" do
        get admin_system_jobs_path

        assert_response :success
        assert_equal "Admin/System/Jobs/Index", inertia.component
        props = inertia.props.deep_symbolize_keys
        assert_equal "/jobs", props.fetch(:dashboardUrl)
        assert_equal false, props.dig(:developerMode, :enabled)
        assert_nil props.dig(:developerMode, :profile)
        assert_equal true, props.fetch(:automaticRegistration)
      end

      test "developer mode warns that cron is paused while manual jobs remain linked" do
        with_unrestricted_developer_mode do
          get admin_system_jobs_path

          assert_response :success
          assert_equal "Admin/System/Jobs/Index", inertia.component
          props = inertia.props.deep_symbolize_keys
          assert_equal "/jobs", props.fetch(:dashboardUrl)
          assert_equal true, props.dig(:developerMode, :enabled)
          assert_equal "unrestricted", props.dig(:developerMode, :profile)
          assert_equal false, props.fetch(:automaticRegistration)
          assert_equal "unrestricted", response.headers["X-McWeb-Developer-Mode"]
          assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
          assert_equal "no-store", response.headers["Cache-Control"]
        end
      end

      private

      def with_unrestricted_developer_mode
        settings = Mcweb::DeveloperMode.parse(
          config: { developer_mode: { enabled: true } },
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
