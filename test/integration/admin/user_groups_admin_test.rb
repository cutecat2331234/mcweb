# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class UserGroupsAdminTest < ActionDispatch::IntegrationTest
    setup do
      @admin = create_user
      %w[
        admin.access
        forum.topics.lock
        identity.groups.manage
        identity.groups.members.assign
        identity.groups.permissions.manage
        identity.groups.read
      ].each { |permission| grant_permission(@admin, permission) }
      @member = create_user
      sign_in_as(@admin)
    end

    test "read endpoints use the dedicated identity group permission" do
      remove_permission(@admin, "identity.groups.read")

      get admin_forum_user_groups_path

      assert_redirected_to root_path
    end

    test "read-only group viewers can inspect details without mutation affordances" do
      group = Community::UserGroup.create!(name: "Read-only group", priority: 1)
      viewer = create_user
      %w[
        admin.access
        identity.groups.read
      ].each { |permission| grant_permission(viewer, permission) }
      delete identity_session_path
      sign_in_as(viewer)

      get admin_forum_user_groups_path
      assert_response :success
      props = inertia.props.deep_symbolize_keys
      assert_empty props.fetch(:actions)
      assert props.fetch(:columns).first.fetch(:link)
      row = props.fetch(:rows).find { |candidate| candidate[:name] == group.name }
      assert_equal edit_admin_forum_user_group_path(group), row[:url]

      get new_admin_forum_user_group_path
      assert_redirected_to root_path
      get edit_admin_forum_user_group_path(group)
      assert_response :success
      detail_props = inertia.props.deep_symbolize_keys
      assert_not detail_props.fetch(:canManageGroup)
      assert_not detail_props.fetch(:canManageMembers)
      assert_not detail_props.fetch(:canManagePermissions)
      assert_nil detail_props.fetch(:submitUrl)
      assert_nil detail_props.fetch(:deleteUrl)
    end

    test "global identity group access does not require an unrelated forum module grant" do
      get admin_forum_user_groups_path

      assert_response :success
    end

    test "staff can enter global identity groups through the identity module grant" do
      staff = create_user(account_type: "staff")
      %w[
        admin.access
        identity.groups.read
      ].each { |permission| grant_permission(staff, permission) }
      grant_admin_module(staff, "identity")
      delete identity_session_path
      sign_in_as(staff)

      get admin_forum_user_groups_path

      assert_response :success
      assert_not staff.admin_module_grants.exists?(module_key: "forum")
    end

    test "group details can be updated without permission-delegation capability" do
      group = Community::UserGroup.create!(
        name: "Existing grants",
        priority: 1,
        permissions: [ "forum.topics.lock" ]
      )
      manager = create_user
      %w[
        admin.access
        identity.groups.read
        identity.groups.manage
      ].each { |permission| grant_permission(manager, permission) }
      delete identity_session_path
      sign_in_as(manager)

      patch admin_forum_user_group_path(group), params: {
        user_group: {
          name: "Renamed without delegation",
          priority: 2,
          color_hex: "",
          banner_text: "",
          is_primary_default: false,
          permissions: [ "forum.topics.lock" ]
        }
      }

      assert_redirected_to admin_forum_user_groups_path
      assert_equal "Renamed without delegation", group.reload.name
      assert_equal [ "forum.topics.lock" ], group.permission_keys
    end

    test "unauthorized write requests cannot read group configuration through errors" do
      group = Community::UserGroup.create!(
        name: "Protected group",
        priority: 1,
        permissions: [ "system.settings.manage" ]
      )
      outsider = create_user
      grant_permission(outsider, "admin.access")
      delete identity_session_path
      sign_in_as(outsider)

      patch admin_forum_user_group_path(group), params: {
        user_group: {
          name: "",
          priority: 1,
          permissions: [ "system.settings.manage" ]
        }
      }

      assert_redirected_to admin_root_path
      assert_equal "Protected group", group.reload.name
    end

    test "controller delegates group and membership writes with audit coverage" do
      post admin_forum_user_groups_path, params: {
        user_group: {
          name: "Global moderators",
          priority: 10,
          color_hex: "#123456",
          banner_text: "Moderator",
          is_primary_default: false,
          permissions: [ "forum.topics.lock" ]
        }
      }
      group = Community::UserGroup.find_by!(name: "Global moderators")
      assert_redirected_to admin_forum_user_groups_path
      assert AuditLog.exists?(action: "identity.group.created", resource_id: group.id)

      patch admin_forum_user_group_path(group), params: {
        user_group: {
          name: "Global senior moderators",
          priority: 20,
          color_hex: "",
          banner_text: "",
          is_primary_default: false,
          permissions: [ "forum.topics.lock" ]
        }
      }
      assert_redirected_to admin_forum_user_groups_path
      assert_equal "Global senior moderators", group.reload.name
      assert AuditLog.exists?(action: "identity.group.updated", resource_id: group.id)

      post add_member_admin_forum_user_group_path(group), params: {
        username: @member.username
      }
      assert_redirected_to edit_admin_forum_user_group_path(group)
      membership = Community::GroupMembership.find_by!(user: @member, user_group: group)
      assert membership.is_primary?
      assert AuditLog.exists?(action: "identity.group.member_added", resource_id: group.id)

      post set_primary_admin_forum_user_group_path(group), params: {
        user_id: @member.id
      }
      assert_redirected_to edit_admin_forum_user_group_path(group)
      assert AuditLog.exists?(action: "identity.group.primary_changed", resource_id: group.id)

      delete remove_member_admin_forum_user_group_path(group), params: {
        user_id: @member.id
      }
      assert_redirected_to edit_admin_forum_user_group_path(group)
      assert_not Community::GroupMembership.exists?(user: @member, user_group: group)
      assert AuditLog.exists?(action: "identity.group.member_removed", resource_id: group.id)

      delete admin_forum_user_group_path(group)
      assert_redirected_to admin_forum_user_groups_path
      assert_not Community::UserGroup.exists?(group.id)
      assert AuditLog.exists?(action: "identity.group.deleted", resource_id: group.id)
    end

    test "unknown permissions and missing mutation grants cannot write" do
      post admin_forum_user_groups_path, params: {
        user_group: {
          name: "Unknown catalog group",
          priority: 1,
          permissions: [ "forum.not_in_catalog" ]
        }
      }
      assert_response :unprocessable_entity
      assert_not Community::UserGroup.exists?(name: "Unknown catalog group")

      remove_permission(@admin, "identity.groups.manage")
      post admin_forum_user_groups_path, params: {
        user_group: {
          name: "Unauthorized group",
          priority: 1,
          permissions: [ "forum.topics.lock" ]
        }
      }
      assert_redirected_to root_path
      assert_not Community::UserGroup.exists?(name: "Unauthorized group")
    end

    test "permission catalog distinguishes new grants from removable existing grants" do
      group = Community::UserGroup.create!(
        name: "Delegation preview",
        priority: 1,
        permissions: [ "system.settings.manage" ]
      )

      get edit_admin_forum_user_group_path(group)

      assert_response :success
      props = inertia.props.deep_symbolize_keys
      permissions = props
        .fetch(:permissionCatalog)
        .flat_map { |domain| domain.fetch(:permissions) }
        .index_by { |permission| permission.fetch(:key) }
      assert_includes props.fetch(:grantablePermissionKeys), "forum.topics.lock"
      assert_not_includes props.fetch(:grantablePermissionKeys), "system.settings.manage"
      assert permissions.fetch("forum.topics.lock").fetch(:grantable)
      assert permissions.fetch("forum.topics.lock").fetch(:delegable)
      assert_not permissions.fetch("system.settings.manage").fetch(:grantable)
      assert permissions.fetch("system.settings.manage").fetch(:delegable),
        "an existing grant must remain operable so an authorized manager can revoke it"
      assert_not permissions.fetch("store.orders.refund").fetch(:grantable)
      assert_not permissions.fetch("store.orders.refund").fetch(:delegable)
    end

    test "high permission groups suppress add-member actions that the actor cannot delegate" do
      group = Community::UserGroup.create!(
        name: "High permission group",
        priority: 100,
        permissions: [ "system.settings.manage" ]
      )

      get edit_admin_forum_user_group_path(group)

      assert_response :success
      props = inertia.props.deep_symbolize_keys
      assert_not props.fetch(:canAddMembers)
      assert_nil props.fetch(:addMemberUrl)
      assert_nil props.fetch(:deleteBlocked),
        "the actor has the separate membership and permission capabilities required for deletion"
    end

    test "delete capability explains each missing action permission combination" do
      group = Community::UserGroup.create!(
        name: "Protected identity group",
        priority: 10,
        permissions: [ "forum.topics.lock" ]
      )
      Community::GroupMembership.create!(
        user: @member,
        user_group: group,
        is_primary: true
      )
      variants = [
        {
          extra_permissions: [ "identity.groups.permissions.manage" ],
          can_manage_members: false,
          can_manage_permissions: true,
          blocked_reason: "members"
        },
        {
          extra_permissions: [ "identity.groups.members.assign" ],
          can_manage_members: true,
          can_manage_permissions: false,
          blocked_reason: "permissions"
        },
        {
          extra_permissions: [],
          can_manage_members: false,
          can_manage_permissions: false,
          blocked_reason: "members_and_permissions"
        }
      ]

      variants.each do |variant|
        manager = create_user
        (
          %w[admin.access identity.groups.read identity.groups.manage] +
          variant.fetch(:extra_permissions)
        ).each { |permission| grant_permission(manager, permission) }
        delete identity_session_path
        sign_in_as(manager)

        get edit_admin_forum_user_group_path(group)

        assert_response :success
        props = inertia.props.deep_symbolize_keys
        assert_equal variant.fetch(:can_manage_members), props.fetch(:canManageMembers)
        assert_equal variant.fetch(:can_manage_permissions), props.fetch(:canManagePermissions)
        assert_not props.fetch(:canAddMembers)
        assert_nil props.fetch(:addMemberUrl)
        assert_equal variant.fetch(:blocked_reason), props.fetch(:deleteBlocked)
        assert_nil props.fetch(:deleteUrl)
      end
    end

    test "safe groups expose add-member actions" do
      group = Community::UserGroup.create!(
        name: "Delegable identity group",
        priority: 10,
        permissions: [ "forum.topics.lock" ]
      )

      get edit_admin_forum_user_group_path(group)

      assert_response :success
      props = inertia.props.deep_symbolize_keys
      assert props.fetch(:canAddMembers)
      assert_equal(
        add_member_admin_forum_user_group_path(group),
        props.fetch(:addMemberUrl)
      )
    end

    test "legacy grants remain visible and removable" do
      group = Community::UserGroup.create!(
        name: "Legacy grants",
        priority: 1,
        permissions: [ "retired.plugin.permission" ]
      )

      get edit_admin_forum_user_group_path(group)

      legacy_group = inertia.props
        .deep_symbolize_keys
        .fetch(:permissionCatalog)
        .find { |domain| domain[:key] == "legacy" }
      assert legacy_group
      assert_equal(
        [ "retired.plugin.permission" ],
        legacy_group.fetch(:permissions).pluck(:key)
      )
      legacy_permission = legacy_group.fetch(:permissions).first
      assert_not legacy_permission.fetch(:grantable)
      assert legacy_permission.fetch(:delegable)

      patch admin_forum_user_group_path(group), params: {
        user_group: {
          name: group.name,
          priority: group.priority,
          is_primary_default: false,
          permissions: []
        }
      }
      assert_redirected_to admin_forum_user_groups_path
      assert_empty group.reload.permission_keys
    end

    test "member list is bounded and paginated without replacing the form shell" do
      group = Community::UserGroup.create!(name: "Large group", priority: 1)
      21.times do
        member = create_user
        Community::GroupMembership.create!(
          user: member,
          user_group: group,
          is_primary: false
        )
      end

      get edit_admin_forum_user_group_path(group)
      first_page = inertia.props.deep_symbolize_keys
      assert_equal 20, first_page.fetch(:members).size
      assert_equal 21, first_page.fetch(:memberTotal)
      assert_equal 1, first_page.fetch(:memberPage)

      get edit_admin_forum_user_group_path(group, member_page: 2)
      second_page = inertia.props.deep_symbolize_keys
      assert_equal 1, second_page.fetch(:members).size
      assert_equal 2, second_page.fetch(:memberPage)
    end

    private

    def remove_permission(user, permission_key)
      permission = Permission.find_by!(key: permission_key)
      user.roles
        .joins(:permissions)
        .where(permissions: { id: permission.id })
        .each { |role| user.roles.delete(role) }
      user.reload
    end
  end
end
