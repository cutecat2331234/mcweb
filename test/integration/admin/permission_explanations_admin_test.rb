# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class PermissionExplanationsAdminTest < ActionDispatch::IntegrationTest
    setup do
      @owner = create_user(account_type: "owner")
      @target = create_user
      sign_in_as(@owner)
    end

    test "authorized administrator sees the server-resolved member perspective" do
      get permissions_admin_user_path(@target)

      assert_response :success
      assert_equal "Admin/Users/Permissions", inertia.component
      props = inertia.props.deep_symbolize_keys
      assert_equal @target.public_id, props.dig(:user, :public_id)
      assert_equal @target.permission_version, props.dig(:user, :permission_version)
      assert_equal Identity::PermissionCatalog.assignable_keys.size, props.dig(:summary, :total)
      assert_equal admin_user_path(@target), props.fetch(:backUrl)
    end

    test "permission explanation uses a separate permission" do
      delete identity_session_path
      reader = create_user(account_type: "staff")
      grant_permission(reader, "admin.access")
      grant_admin_module(reader, "system")
      sign_in_as(reader)

      get permissions_admin_user_path(@target)

      assert_redirected_to root_path
    end

    test "member detail exposes a real permission explanation action" do
      get admin_user_path(@target)

      assert_response :success
      action = inertia.props.deep_symbolize_keys.fetch(:actions).find do |entry|
        entry[:href] == permissions_admin_user_path(@target)
      end
      assert action
      assert_equal "get", action.fetch(:method)
    end
  end
end
