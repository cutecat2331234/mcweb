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
      assert_equal "Admin/Roles/Index", inertia.component
      assert_equal false, inertia.props.deep_symbolize_keys.fetch(:canManage)
      assert_nil inertia.props.deep_symbolize_keys[:newUrl]
      get admin_role_path(@role)
      assert_response :success
      assert_equal "Admin/Roles/Show", inertia.component
      assert_nil inertia.props.deep_symbolize_keys[:editUrl]

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

      get new_admin_role_path
      assert_response :success
      assert_equal "Admin/Roles/Form", inertia.component
      assert_equal true, inertia.props.deep_symbolize_keys.fetch(:canManage)

      get edit_admin_role_path(created_role)
      assert_response :success
      assert_equal "Admin/Roles/Form", inertia.component
      assert_equal delegated_permission.id,
        inertia.props.deep_symbolize_keys.dig(:role, :permissionIds).sole
    end

    test "destroy requires and applies a replacement for an assigned role" do
      owner = create_user(account_type: "owner")
      grant_permission(owner, "admin.access")
      grant_admin_module(owner, "system")
      member = create_user
      replacement = Role.create!(
        name: "Replacement role",
        key: "replacement_role_#{SecureRandom.hex(4)}"
      )
      member.roles << @role
      sign_in_as(owner)

      delete admin_role_path(@role)

      assert_redirected_to edit_admin_role_path(@role)
      assert Role.exists?(@role.id)
      assert UserRole.exists?(user: member, role: @role)

      delete admin_role_path(@role), params: {
        role: { replacement_role_id: replacement.id }
      }

      assert_redirected_to admin_roles_path
      assert_not Role.exists?(@role.id)
      assert UserRole.exists?(user: member, role: replacement)
    end
  end
end
