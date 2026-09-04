# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  module System
    class SidekiqAdminTest < ActionDispatch::IntegrationTest
      setup do
        @admin = create_user
        grant_permission(@admin, "admin.access")
        grant_permission(@admin, "system.sidekiq.read")
        grant_admin_module(@admin, "system")
        sign_in_as(@admin)
      end

      test "renders a fixed same-origin Sidekiq console URL" do
        get admin_system_sidekiq_path, params: { src: "https://example.test" }

        assert_response :success
        assert_equal "Admin/System/Sidekiq/Index", inertia.component
        props = inertia.props.deep_symbolize_keys
        assert_equal "/jobs/", props.fetch(:sidekiqUrl)
        assert_not props.key?(:src)
      end

      test "preserves a safe deep link and drops unowned query fields" do
        get "/admin/system/sidekiq/retries/job.123", params: {
          page: "2",
          poll: "true",
          count: "0",
          period: "forever",
          src: "https://example.test",
          token: "must-not-be-forwarded"
        }

        assert_response :success
        props = inertia.props.deep_symbolize_keys
        assert_equal "/jobs/retries/job.123?poll=true", props.fetch(:sidekiqUrl)
        assert_not_includes props.fetch(:sidekiqUrl), "src"
        assert_not_includes props.fetch(:sidekiqUrl), "token"
      end

      test "rejects an invalid or unbounded deep link" do
        get "/admin/system/sidekiq/#{'a' * 513}"

        assert_response :not_found

        get "/admin/system/sidekiq/stats"

        assert_response :not_found

        get "/admin/system/sidekiq/profiles/profile-key/data"

        assert_response :not_found
      end

      test "accepts a Sidekiq Cron HTML deep link" do
        get "/admin/system/sidekiq/cron/namespaces/default"

        assert_response :success
        props = inertia.props.deep_symbolize_keys
        assert_equal "/jobs/cron/namespaces/default", props.fetch(:sidekiqUrl)
      end

      test "canonicalizes a long metrics detail period to Sidekiq semantics" do
        get "/admin/system/sidekiq/metrics/ExampleWorker", params: {
          period: "72h"
        }

        assert_response :success
        props = inertia.props.deep_symbolize_keys
        assert_equal "/jobs/metrics/ExampleWorker?period=8h",
          props.fetch(:sidekiqUrl)
      end

      test "generic jobs read permission no longer authorizes Sidekiq" do
        reader = create_user
        grant_permission(reader, "admin.access")
        grant_permission(reader, "system.jobs.read")
        grant_admin_module(reader, "system")
        delete identity_session_path
        sign_in_as(reader)

        get admin_system_sidekiq_path

        assert_redirected_to root_path
      end

      test "requires access to the system admin module" do
        reader = create_user
        grant_permission(reader, "admin.access")
        grant_permission(reader, "system.sidekiq.read")
        grant_admin_module(reader, "forum")
        delete identity_session_path
        sign_in_as(reader)

        get admin_system_sidekiq_path

        assert_redirected_to admin_root_path
      end
    end

    class SidekiqAdminAuthenticationTest < ActionDispatch::IntegrationTest
      test "an unauthenticated deep link preserves the administrator return path" do
        get "/admin/system/sidekiq/retries?substr=mailer"

        assert_redirected_to identity_sign_in_path
        assert_equal "/admin/system/sidekiq/retries?substr=mailer",
          session[:return_to]
      end
    end
  end
end
