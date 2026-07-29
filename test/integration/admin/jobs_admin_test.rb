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
        assert_equal admin_system_jobs_path, props.fetch(:metricsUrl)
        assert_equal false, props.dig(:developerMode, :enabled)
        assert_nil props.dig(:developerMode, :profile)
        assert_equal true, props.fetch(:automaticRegistration)
        assert_equal "test", props.dig(:queueSnapshot, :adapter)
        assert_equal "local", props.dig(:queueSnapshot, :status)
        assert_equal [], props.dig(:queueSnapshot, :queues)
        assert_equal true, props.dig(:workerHeartbeat, :available)
        assert_equal "missing", props.dig(:workerHeartbeat, :status)
        assert_equal 0, props.dig(:workerHeartbeat, :fresh_count)
        assert_equal true, props.dig(:operationsMetrics, :available)
        assert_equal "24h", props.dig(:operationsMetrics, :range)
        assert_equal false, props.dig(:operationsMetrics, :truncated)
        assert_operator props.dig(:operationsMetrics, :row_count), :<=, 5_000
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
          assert_equal "local", props.dig(:queueSnapshot, :status)
          assert_equal "missing", props.dig(:workerHeartbeat, :status)
          assert_equal "unrestricted", response.headers["X-McWeb-Developer-Mode"]
          assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
          assert_equal "no-store", response.headers["Cache-Control"]
        end
      end

      test "range selection returns a bounded operations trend prop" do
        get admin_system_jobs_path, params: { range: "7d" }

        assert_response :success
        props = inertia.props.deep_symbolize_keys
        assert_equal "7d", props.dig(:operationsMetrics, :range)
        assert_equal 21_600, props.dig(
          :operationsMetrics,
          :resolution_seconds
        )
        assert_equal %w[1h 6h 24h 7d 30d],
          props.dig(:operationsMetrics, :ranges)
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
