# frozen_string_literal: true

require "test_helper"
require Rails.root.join(
  "db/migrate/20260728190000_add_shared_core_permissions"
)

class SharedCorePermissionsMigrationTest < ActiveSupport::TestCase
  test "upgrade idempotently provisions shared permissions and system-role grants" do
    roles = %w[owner super_admin forum_admin].index_with do |key|
      Role.find_or_create_by!(key:) do |role|
        role.name = key
        role.system_role = true
      end
    end
    staff = create_user(account_type: "staff")
    staff.roles << roles.fetch("forum_admin")
    forum_grant = staff.admin_module_grants.create!(
      module_key: "forum",
      granted_at: 1.day.ago
    )
    stale = Permission.find_or_initialize_by(key: "store.products.read")
    stale.update!(name: "stale", category: "legacy", description: "stale")

    migration = AddSharedCorePermissions.new
    migration.up
    migration.up

    assert_equal AddSharedCorePermissions::PERMISSIONS.pluck(:key).sort,
      Permission.where(key: AddSharedCorePermissions::PERMISSIONS.pluck(:key)).pluck(:key).sort
    assert_equal "store", stale.reload.category
    assert_equal "查看商城工作人员通知", stale.name

    AddSharedCorePermissions::PERMISSIONS.each do |attributes|
      permission = Permission.find_by!(key: attributes.fetch(:key))
      expected_roles =
        if (
          AddSharedCorePermissions::IDENTITY_GROUP_PERMISSION_KEYS +
          %w[forum.users.trust.manage]
        ).include?(attributes.fetch(:key))
          %w[forum_admin owner super_admin]
        else
          %w[owner super_admin]
        end

      assert_equal expected_roles,
        permission.roles.where(id: roles.values.map(&:id)).pluck(:key).sort
    end

    identity_grant = staff.admin_module_grants.find_by!(module_key: "identity")
    assert_equal forum_grant.granted_at.to_i, identity_grant.granted_at.to_i
  end

  test "identity module backfill is limited to eligible existing staff" do
    forum_admin = Role.find_or_create_by!(key: "forum_admin") do |role|
      role.name = "forum_admin"
      role.system_role = true
    end
    staff_without_forum_scope = create_user(account_type: "staff")
    staff_without_forum_scope.roles << forum_admin
    staff_without_group_management = create_user(account_type: "staff")
    staff_without_group_management.admin_module_grants.create!(
      module_key: "forum",
      granted_at: Time.current
    )
    member_with_forum_scope = create_user
    member_with_forum_scope.roles << forum_admin
    member_with_forum_scope.admin_module_grants.create!(
      module_key: "forum",
      granted_at: Time.current
    )

    AddSharedCorePermissions.new.up

    assert_not staff_without_forum_scope.admin_module_grants.exists?(module_key: "identity")
    assert_not staff_without_group_management.admin_module_grants.exists?(module_key: "identity")
    assert_not member_with_forum_scope.admin_module_grants.exists?(module_key: "identity")
  end

  test "custom legacy forum managers retain identity group access after upgrade" do
    legacy_permission = Permission.find_or_create_by!(key: "forum.sections.manage") do |permission|
      permission.name = "Manage forum sections"
      permission.category = "forum"
    end
    custom_role = Role.create!(
      key: "custom_group_manager_#{SecureRandom.hex(4)}",
      name: "Custom group manager"
    )
    custom_role.permissions << legacy_permission
    staff = create_user(account_type: "staff")
    staff.roles << custom_role
    staff.admin_module_grants.create!(
      module_key: "forum",
      granted_at: Time.current
    )

    AddSharedCorePermissions.new.up

    assert_equal(
      AddSharedCorePermissions::IDENTITY_GROUP_PERMISSION_KEYS.sort,
      custom_role.permissions
        .where(key: AddSharedCorePermissions::IDENTITY_GROUP_PERMISSION_KEYS)
        .pluck(:key)
        .sort
    )
    assert staff.admin_module_grants.exists?(module_key: "identity")
  end

  test "legacy identity-group managers receive group permissions and identity module access" do
    legacy_group = Community::UserGroup.create!(
      name: "Legacy group managers",
      priority: 10,
      permissions: [ "forum.sections.manage" ]
    )
    staff = create_user(account_type: "staff")
    Community::GroupMembership.create!(
      user: staff,
      user_group: legacy_group,
      is_primary: true
    )
    staff.admin_module_grants.create!(
      module_key: "forum",
      granted_at: 2.days.ago
    )

    migration = AddSharedCorePermissions.new
    migration.up
    migration.up

    expected_permissions = (
      [ "forum.sections.manage" ] +
      AddSharedCorePermissions::IDENTITY_GROUP_PERMISSION_KEYS
    ).sort
    assert_equal expected_permissions, legacy_group.reload.permission_keys.sort
    assert_equal expected_permissions.size, legacy_group.permission_keys.uniq.size
    assert staff.admin_module_grants.exists?(module_key: "identity")
    assert_equal 1, staff.admin_module_grants.where(module_key: "identity").count
  end

  test "legacy system managers receive role and ban permissions idempotently" do
    settings_permission = Permission.find_or_create_by!(key: "system.settings.manage") do |permission|
      permission.name = "Manage system settings"
      permission.category = "system"
    end
    legacy_role = Role.create!(
      name: "Legacy system role",
      key: "legacy_system_role_#{SecureRandom.hex(4)}",
      permissions: [ settings_permission ]
    )
    legacy_group = Community::UserGroup.create!(
      name: "Legacy system identity group",
      priority: 20,
      permissions: [ settings_permission.key ]
    )

    migration = AddSharedCorePermissions.new
    migration.up
    migration.up

    expected_permissions = (
      AddSharedCorePermissions::IDENTITY_ROLE_PERMISSION_KEYS +
      AddSharedCorePermissions::SYSTEM_BAN_PERMISSION_KEYS
    ).sort
    assert_equal expected_permissions,
      legacy_role.permissions.where(key: expected_permissions).pluck(:key).sort
    assert_equal expected_permissions,
      legacy_group.reload.permission_keys.intersection(expected_permissions).sort
    expected_permissions.each do |permission_key|
      assert_equal 1,
        legacy_role.role_permissions.joins(:permission)
          .where(permissions: { key: permission_key })
          .count
      assert_equal 1, legacy_group.permission_keys.count(permission_key)
    end
  end

  test "rollback is explicit because pre-existing grants cannot be distinguished" do
    migration = AddSharedCorePermissions.new
    migration.up

    assert_raises(ActiveRecord::IrreversibleMigration) do
      migration.down
    end

    assert Permission.exists?(key: "store.products.read")
    assert Permission.exists?(key: "forum.conversations.create")
  end
end
