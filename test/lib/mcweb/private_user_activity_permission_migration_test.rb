# frozen_string_literal: true

require "test_helper"
require Rails.root.join(
  "db/migrate/20260823100000_add_private_user_activity_read_permission"
)

class PrivateUserActivityPermissionMigrationTest < ActiveSupport::TestCase
  test "upgrade normalizes metadata and grants only privileged defaults idempotently" do
    permission_key = AddPrivateUserActivityReadPermission::PERMISSION_KEY
    permission_ids = Permission.where(key: permission_key).select(:id)
    RolePermission.where(permission_id: permission_ids).delete_all
    Permission.where(key: permission_key).delete_all

    roles = %w[owner super_admin forum_admin].index_with do |key|
      Role.find_or_create_by!(key: key) do |role|
        role.name = key.humanize
        role.system_role = true
      end
    end
    custom_role = Role.create!(
      key: "private_activity_reader_#{SecureRandom.hex(4)}",
      name: "Private activity reader"
    )
    migration = AddPrivateUserActivityReadPermission.new

    migration.up

    permission = Permission.find_by!(key: permission_key)
    assert_equal "View private member activity", permission.name
    assert_equal "identity", permission.category
    assert_equal AddPrivateUserActivityReadPermission::PRIVILEGED_ROLE_KEYS.sort,
      permission.roles.pluck(:key).sort
    assert_not_includes permission.roles, roles.fetch("forum_admin")

    custom_role.permissions << permission
    permission.update_columns(name: "stale", category: "stale", description: "stale")
    migration.up

    permission.reload
    assert_equal "View private member activity", permission.name
    assert_equal "identity", permission.category
    assert_equal "View private presence, commerce, points, check-in, and game-activity details",
      permission.description
    assert_equal(
      (AddPrivateUserActivityReadPermission::PRIVILEGED_ROLE_KEYS + [ custom_role.key ]).sort,
      permission.roles.pluck(:key).sort
    )
    assert_equal permission.roles.pluck(:id).uniq.sort, permission.roles.pluck(:id).sort
  end

  test "rollback is explicit because later grants cannot be identified safely" do
    assert_raises(ActiveRecord::IrreversibleMigration) do
      AddPrivateUserActivityReadPermission.new.down
    end
  end
end
