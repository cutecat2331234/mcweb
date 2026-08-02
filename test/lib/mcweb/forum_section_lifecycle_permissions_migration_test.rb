# frozen_string_literal: true

require "test_helper"
require Rails.root.join(
  "db/migrate/20260802100000_add_forum_section_lifecycle_permissions"
)

class ForumSectionLifecyclePermissionsMigrationTest < ActiveSupport::TestCase
  test "upgrade provisions lifecycle permissions and preserves legacy grants idempotently" do
    default_roles = AddForumSectionLifecyclePermissions::DEFAULT_ROLE_KEYS.index_with do |key|
      Role.find_or_create_by!(key:) do |role|
        role.name = key
        role.system_role = true
      end
    end
    legacy_permission = Permission.find_or_create_by!(
      key: AddForumSectionLifecyclePermissions::LEGACY_PERMISSION_KEY
    ) do |permission|
      permission.name = "Manage forum sections"
      permission.category = "forum"
    end
    custom_role = Role.create!(
      key: "legacy_section_manager_#{SecureRandom.hex(4)}",
      name: "Legacy section manager"
    )
    custom_role.permissions << legacy_permission
    legacy_group = Community::UserGroup.create!(
      name: "Legacy section managers #{SecureRandom.hex(4)}",
      permissions: [ legacy_permission.key ]
    )

    migration = AddForumSectionLifecyclePermissions.new
    migration.up
    migration.up

    AddForumSectionLifecyclePermissions::PERMISSIONS.each do |attributes|
      permission = Permission.find_by!(key: attributes.fetch(:key))

      assert_equal "forum", permission.category
      assert_equal(
        AddForumSectionLifecyclePermissions::DEFAULT_ROLE_KEYS.sort,
        permission.roles.where(id: default_roles.values.map(&:id)).pluck(:key).sort
      )
      assert_equal 1,
        custom_role.role_permissions.joins(:permission)
          .where(permissions: { key: permission.key })
          .count
      assert_equal 1, legacy_group.reload.permission_keys.count(permission.key)
    end
  end

  test "rollback is explicit because inherited grants cannot be identified safely" do
    assert_raises(ActiveRecord::IrreversibleMigration) do
      AddForumSectionLifecyclePermissions.new.down
    end
  end
end
