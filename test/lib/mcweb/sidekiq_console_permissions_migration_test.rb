# frozen_string_literal: true

require "test_helper"
require Rails.root.join(
  "db/migrate/20260824231500_add_sidekiq_console_permissions"
)

class SidekiqConsolePermissionsMigrationTest < ActiveSupport::TestCase
  test "upgrade provisions dedicated permissions and preserves legacy access idempotently" do
    default_roles = AddSidekiqConsolePermissions::DEFAULT_ROLE_KEYS.index_with do |key|
      Role.find_or_create_by!(key:) do |role|
        role.name = key.humanize
        role.system_role = true
      end
    end
    legacy_read = legacy_permission("system.jobs.read")
    legacy_manage = legacy_permission("system.jobs.manage")
    read_role = custom_role("sidekiq_legacy_reader")
    manage_role = custom_role("sidekiq_legacy_manager")
    unrelated_role = custom_role("sidekiq_unrelated")
    read_role.permissions << legacy_read
    manage_role.permissions << legacy_manage
    read_group = legacy_group("Sidekiq legacy readers", [ legacy_read.key ])
    manage_group = legacy_group("Sidekiq legacy managers", [ legacy_manage.key ])
    unrelated_group = legacy_group("Sidekiq unrelated", [ "admin.access" ])

    migration = AddSidekiqConsolePermissions.new
    migration.up
    migration.up

    permissions = Permission.where(
      key: AddSidekiqConsolePermissions::PERMISSION_KEYS
    ).index_by(&:key)
    assert_equal AddSidekiqConsolePermissions::PERMISSION_KEYS.sort,
      permissions.keys.sort
    assert_equal %w[system.sidekiq.read],
      sidekiq_grants(read_role)
    assert_equal %w[system.sidekiq.manage system.sidekiq.read],
      sidekiq_grants(manage_role)
    assert_empty sidekiq_grants(unrelated_role)
    assert_equal %w[system.sidekiq.read],
      sidekiq_group_grants(read_group)
    assert_equal %w[system.sidekiq.manage system.sidekiq.read],
      sidekiq_group_grants(manage_group)
    assert_empty sidekiq_group_grants(unrelated_group)

    permissions.each_value do |permission|
      assert_equal "system", permission.category
      assert_equal AddSidekiqConsolePermissions::DEFAULT_ROLE_KEYS.sort,
        permission.roles.where(id: default_roles.values.map(&:id)).pluck(:key).sort
    end
  end

  test "rollback is explicit because inherited grants cannot be distinguished safely" do
    assert_raises(ActiveRecord::IrreversibleMigration) do
      AddSidekiqConsolePermissions.new.down
    end
  end

  private

  def legacy_permission(key)
    Permission.find_or_create_by!(key:) do |permission|
      permission.name = key
      permission.category = "system"
    end
  end

  def custom_role(prefix)
    Role.create!(
      key: "#{prefix}_#{SecureRandom.hex(4)}",
      name: prefix.humanize
    )
  end

  def legacy_group(prefix, permissions)
    Community::UserGroup.create!(
      name: "#{prefix} #{SecureRandom.hex(4)}",
      permissions:
    )
  end

  def sidekiq_grants(role)
    role.permissions.where(key: AddSidekiqConsolePermissions::PERMISSION_KEYS)
      .pluck(:key)
      .sort
  end

  def sidekiq_group_grants(group)
    group.reload.permission_keys
      .intersection(AddSidekiqConsolePermissions::PERMISSION_KEYS)
      .sort
  end
end
