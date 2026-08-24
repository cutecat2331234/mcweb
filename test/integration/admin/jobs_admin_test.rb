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
        assert_equal admin_system_jobs_path, props.fetch(:metricsUrl)
        assert_equal false, props.dig(:developerMode, :enabled)
        assert_nil props.dig(:developerMode, :profile)
        assert_equal true, props.fetch(:automaticRegistration)
        assert_equal "test", props.dig(:queueSnapshot, :adapter)
        assert_equal "local", props.dig(:queueSnapshot, :status)
        assert_equal [], props.dig(:queueSnapshot, :queues)
        assert_equal "local", props.dig(:redisRecovery, :status)
        assert_nil props.dig(:redisRecovery, :redis_available)
        assert_equal true, props.dig(:redisRecovery, :ledger_available)
        assert_equal false, props.dig(:redisRecovery, :database_fallback)
        assert props.dig(:redisRecoveryCopy, :title).present?
        assert props.dig(:redisRecoveryCopy, :handoffNote).present?
        assert_equal true, props.dig(:workerHeartbeat, :available)
        assert_equal "missing", props.dig(:workerHeartbeat, :status)
        assert_equal 0, props.dig(:workerHeartbeat, :fresh_count)
        assert_equal true, props.dig(:operationsMetrics, :available)
        assert_equal "24h", props.dig(:operationsMetrics, :range)
        assert_equal false, props.dig(:operationsMetrics, :truncated)
        assert_equal [], props.fetch(:securityRecoveryDeliveries)
        assert props.dig(:securityRecoveryCopy, :title).present?
        assert_operator props.dig(:operationsMetrics, :row_count), :<=, 5_000
      end

      test "jobs page exposes recent security recovery delivery state without secrets" do
        recovery_user = create_user
        request_result = Identity::ResetPassword.call(
          email: recovery_user.email,
          ip_address: "203.0.113.20",
          user_agent: "Jobs audit test"
        )
        token = request_result.value.fetch(:reset_token)
        intent = request_result.value.fetch(:delivery_intent)

        get admin_system_jobs_path

        assert_response :success
        delivery = inertia.props.deep_symbolize_keys
          .fetch(:securityRecoveryDeliveries)
          .find { |row| row.fetch(:publicId) == intent.public_id }
        assert delivery
        assert_equal recovery_user.id, delivery.fetch(:userId)
        assert_equal "password_reset", delivery.fetch(:purpose)
        assert_equal "pending", delivery.fetch(:status)
        assert_equal false, delivery.fetch(:retryable)
        refute_includes delivery.to_json, token
      end

      test "developer mode warns that cron is paused while manual jobs remain linked" do
        with_unrestricted_developer_mode do
          get admin_system_jobs_path

          assert_response :success
          assert_equal "Admin/System/Jobs/Index", inertia.component
          props = inertia.props.deep_symbolize_keys
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

      test "downstream task arguments are rendered from schema and accepted without controller key changes" do
        grant_permission(@admin, "system.jobs.manage")
        @admin.reload

        registrar = lambda do |registry|
          registry.register(
            key: "downstream.profile.transition",
            label_key: "downstream.title",
            description_key: "downstream.description",
            permissions: [ "system.jobs.manage" ],
            argument_schema: {
              "profile_id" => {
                type: "integer",
                required: true,
                minimum: 1,
                label_key: "downstream.profile_id"
              },
              "desired_state_ids" => {
                type: "integer_list",
                required: true,
                minimum: 1,
                maximum_items: 20
              }
            }
          ) { |_run| { changed: true } }
        end

        with_manual_task_registrar(registrar) do
          get admin_system_jobs_path
          assert_response :success
          task = inertia.props.deep_symbolize_keys.fetch(:manualTasks).find do |candidate|
            candidate.fetch(:key) == "downstream.profile.transition"
          end
          assert task
          assert_equal %w[profile_id desired_state_ids], task.fetch(:arguments).pluck(:key)
          assert_equal "downstream.profile_id", task.dig(:arguments, 0, :labelKey)

          assert_enqueued_with(job: Operations::RunManualTaskJob) do
            post run_admin_system_jobs_path, params: {
              task_key: "downstream.profile.transition",
              idempotency_key: "downstream-transition-1",
              arguments: {
                profile_id: "42",
                desired_state_ids: "3, 5 5"
              }
            }
          end
          assert_redirected_to admin_system_jobs_path
          run = Operations::ManualTaskRun.find_by!(
            task_key: "downstream.profile.transition",
            idempotency_key: "downstream-transition-1"
          )
          assert_equal 42, run.arguments.fetch("profile_id")
          assert_equal [ 3, 5 ], run.arguments.fetch("desired_state_ids")
        end
      end

      test "unknown nested task arguments are rejected before enqueue" do
        grant_permission(@admin, "system.jobs.manage")
        @admin.reload

        registrar = lambda do |registry|
          registry.register(
            key: "downstream.profile.refresh",
            label_key: "downstream.title",
            description_key: "downstream.description",
            permissions: [ "system.jobs.manage" ],
            argument_schema: {
              "profile_id" => { type: "integer", required: true, minimum: 1 }
            }
          ) { |_run| { refreshed: true } }
        end

        with_manual_task_registrar(registrar) do
          assert_no_enqueued_jobs do
            assert_no_difference("Operations::ManualTaskRun.count") do
              post run_admin_system_jobs_path, params: {
                task_key: "downstream.profile.refresh",
                idempotency_key: "unknown-argument",
                arguments: {
                  profile_id: "42",
                  command: "arbitrary input"
                }
              }
            end
          end
          assert_redirected_to admin_system_jobs_path
        end
      end

      private

      def with_manual_task_registrar(registrar)
        previous = Array(
          Rails.application.config.x.operations_manual_task_registrars
        ).dup
        Rails.application.config.x.operations_manual_task_registrars = previous + [ registrar ]
        Operations::ManualTaskCatalog.reset_registry!
        yield
      ensure
        Rails.application.config.x.operations_manual_task_registrars = previous
        Operations::ManualTaskCatalog.reset_registry!
      end

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
