# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class RolesAdminTest < ActionDispatch::IntegrationTest
    setup do
      @role = Role.create!(
        name: "Visible role",
        key: "visible_role_#{SecureRandom.hex(4)}"
      )
    end

    test "read permission allows index and show without allowing mutations" do
      viewer = create_user
      %w[admin.access identity.roles.read].each do |permission|
        grant_permission(viewer, permission)
      end
      sign_in_as(viewer)

      get admin_roles_path
      assert_response :success
      get admin_role_path(@role)
      assert_response :success

      post admin_roles_path, params: {
        role: {
          name: "Unauthorized role",
          key: "unauthorized_role_#{SecureRandom.hex(4)}"
        }
      }
      assert_redirected_to root_path
      assert_not Role.exists?(name: "Unauthorized role")

      patch admin_role_path(@role), params: {
        role: { name: "Unauthorized rename", key: @role.key }
      }
      assert_redirected_to root_path
      assert_equal "Visible role", @role.reload.name

      delete admin_role_path(@role)
      assert_redirected_to root_path
      assert Role.exists?(@role.id)
    end

    test "manage permission does not bypass the separate read permission" do
      manager_without_read = create_user
      %w[admin.access identity.roles.manage].each do |permission|
        grant_permission(manager_without_read, permission)
      end
      sign_in_as(manager_without_read)

      get admin_roles_path
      assert_redirected_to root_path

      post admin_roles_path, params: {
        role: {
          name: "Write without read",
          key: "write_without_read_#{SecureRandom.hex(4)}"
        }
      }
      assert_redirected_to root_path
      assert_not Role.exists?(name: "Write without read")
    end

    test "read and manage permissions together allow a bounded role mutation" do
      manager = create_user
      %w[
        admin.access
        forum.topics.lock
        identity.roles.manage
        identity.roles.read
      ].each { |permission| grant_permission(manager, permission) }
      delegated_permission = Permission.find_by!(key: "forum.topics.lock")
      sign_in_as(manager)

      post admin_roles_path, params: {
        role: {
          name: "Topic moderator",
          key: "topic_moderator_#{SecureRandom.hex(4)}",
          description: "Can moderate topics",
          permission_ids: [ delegated_permission.id ]
        }
      }

      created_role = Role.find_by!(name: "Topic moderator")
      assert_redirected_to admin_role_path(created_role)
      assert_equal [ delegated_permission.key ], created_role.permissions.pluck(:key)
    end
  end
end
