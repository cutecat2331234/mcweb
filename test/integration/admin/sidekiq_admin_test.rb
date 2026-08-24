# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  module System
    class SidekiqAdminTest < ActionDispatch::IntegrationTest
      setup do
        @admin = create_user
        grant_permission(@admin, "admin.access")
        grant_permission(@admin, "system.jobs.read")
        grant_admin_module(@admin, "system")
        sign_in_as(@admin)
      end

      test "renders the fixed Sidekiq console host without accepting a frame URL" do
        get admin_system_sidekiq_path, params: { src: "https://example.test" }

        assert_response :success
        assert_equal "Admin/System/Sidekiq/Index", inertia.component
        props = inertia.props.deep_symbolize_keys
        assert_not props.key?(:sidekiqUrl)
        assert_not props.key?(:src)
      end

      test "requires the same read permission as the Sidekiq mount" do
        reader = create_user
        grant_permission(reader, "admin.access")
        grant_admin_module(reader, "system")
        sign_in_as(reader)

        get admin_system_sidekiq_path

        assert_redirected_to root_path
      end

      test "requires access to the system admin module" do
        reader = create_user
        grant_permission(reader, "admin.access")
        grant_permission(reader, "system.jobs.read")
        grant_admin_module(reader, "forum")
        sign_in_as(reader)

        get admin_system_sidekiq_path

        assert_redirected_to admin_root_path
      end
    end
  end
end
