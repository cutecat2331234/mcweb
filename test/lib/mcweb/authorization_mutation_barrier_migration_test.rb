# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20260822090000_enforce_authorization_mutation_barrier")

module Mcweb
  class AuthorizationMutationBarrierMigrationTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    MIGRATION_VERSION = 20260822090000
    TRIGGER_TABLES = EnforceAuthorizationMutationBarrier::TRIGGERS.freeze

    setup do
      migrate_up!
      @users = []
      @roles = []
      @permissions = []
      @groups = []
    end

    teardown do
      migrate_up!
      Community::GroupMembership.where(user_id: @users.map(&:id)).delete_all
      RolePermission.where(role_id: @roles.map(&:id)).delete_all
      UserRole.where(user_id: @users.map(&:id)).delete_all
      Community::UserGroup.where(id: @groups.map(&:id)).delete_all
      Role.where(id: @roles.map(&:id)).delete_all
      Permission.where(id: @permissions.map(&:id)).delete_all
      User.where(id: @users.map(&:id)).destroy_all
    end

    test "all direct authorization mutation events bump each affected user once per statement" do
      first, second = 2.times.map { tracked_user }
      first_role, second_role = 2.times.map { tracked_role }
      first_permission, second_permission = 2.times.map { tracked_permission }
      first_group, second_group = 2.times.map { tracked_group }
      now = Time.current

      assert_single_bump(first) do
        UserRole.insert_all!([
          { user_id: first.id, role_id: first_role.id, created_at: now, updated_at: now },
          { user_id: first.id, role_id: second_role.id, created_at: now, updated_at: now }
        ])
      end
      assert_single_bump(first, second) do
        UserRole.where(user_id: first.id).update_all(user_id: second.id, updated_at: now)
      end
      assert_single_bump(second) do
        UserRole.where(user_id: second.id).delete_all
      end

      UserRole.insert_all!([
        { user_id: first.id, role_id: first_role.id, created_at: now, updated_at: now },
        { user_id: second.id, role_id: second_role.id, created_at: now, updated_at: now }
      ])
      assert_single_bump(first) do
        RolePermission.insert_all!([
          { role_id: first_role.id, permission_id: first_permission.id, created_at: now, updated_at: now },
          { role_id: first_role.id, permission_id: second_permission.id, created_at: now, updated_at: now }
        ])
      end
      assert_single_bump(first, second) do
        RolePermission.where(role_id: first_role.id).update_all(role_id: second_role.id, updated_at: now)
      end
      assert_single_bump(second) do
        RolePermission.where(role_id: second_role.id).delete_all
      end

      assert_single_bump(first) do
        Community::GroupMembership.insert_all!([
          {
            user_id: first.id,
            community_user_group_id: first_group.id,
            is_primary: true,
            created_at: now,
            updated_at: now
          },
          {
            user_id: first.id,
            community_user_group_id: second_group.id,
            is_primary: false,
            created_at: now,
            updated_at: now
          }
        ])
      end
      assert_single_bump(first, second) do
        Community::GroupMembership.where(user_id: first.id)
          .update_all(user_id: second.id, updated_at: now)
      end
      assert_single_bump(second) do
        Community::GroupMembership.where(user_id: second.id).delete_all
      end

      Community::GroupMembership.create!(user: first, user_group: first_group, is_primary: true)
      assert_single_bump(first) do
        Community::UserGroup.where(id: first_group.id)
          .update_all(permissions: [ "forum.database.trigger" ], updated_at: now)
      end

      assert_single_bump(first) do
        User.where(id: first.id).update_all(status: "banned")
      end
      assert_single_bump(first) do
        User.where(id: first.id).update_all(account_type: "staff")
      end
    end

    test "normal model writes bump once and metadata-only updates do not bump" do
      user = tracked_user
      role = tracked_role
      permission = tracked_permission
      group = tracked_group

      user_role = nil
      assert_single_bump(user) do
        user_role = UserRole.create!(user: user, role: role)
      end
      assert_no_bump(user) { user_role.update!(updated_at: Time.current) }

      role_permission = nil
      assert_single_bump(user) do
        role_permission = RolePermission.create!(role: role, permission: permission)
      end
      assert_no_bump(user) { role_permission.update!(updated_at: Time.current) }
      assert_single_bump(user) { role_permission.destroy! }

      membership = nil
      assert_single_bump(user) do
        membership = Community::GroupMembership.create!(
          user: user,
          user_group: group,
          is_primary: false
        )
      end
      assert_no_bump(user) { membership.update!(is_primary: true) }
      assert_no_bump(user) { group.update!(priority: group.priority + 1) }
      assert_single_bump(user) { group.update!(permissions: [ "forum.database.model_write" ]) }
      assert_single_bump(user) { membership.destroy! }

      assert_single_bump(user) { user_role.destroy! }
    end

    test "association clear and delete_all paths are covered by database triggers" do
      user = tracked_user
      roles = 2.times.map { tracked_role }
      permissions = 2.times.map { tracked_permission }
      groups = 2.times.map { tracked_group }
      now = Time.current

      UserRole.insert_all!(roles.map do |role|
        { user_id: user.id, role_id: role.id, created_at: now, updated_at: now }
      end)
      assert_single_bump(user) { user.roles.clear }

      UserRole.insert_all!(roles.map do |role|
        { user_id: user.id, role_id: role.id, created_at: now, updated_at: now }
      end)
      assert_single_bump(user) { user.user_roles.delete_all }

      UserRole.create!(user: user, role: roles.first)
      RolePermission.insert_all!(permissions.map do |permission|
        { role_id: roles.first.id, permission_id: permission.id, created_at: now, updated_at: now }
      end)
      assert_single_bump(user) { roles.first.permissions.clear }

      Community::GroupMembership.insert_all!(groups.each_with_index.map do |group, index|
        {
          user_id: user.id,
          community_user_group_id: group.id,
          is_primary: index.zero?,
          created_at: now,
          updated_at: now
        }
      end)
      assert_single_bump(user) { user.user_groups.clear }
    end

    test "actual rollback and rerunnable up restore the complete trigger contract" do
      assert_trigger_contract

      migrate_down!
      assert_empty installed_trigger_names

      migration = EnforceAuthorizationMutationBarrier.new
      connection.transaction { migration.migrate(:up) }
      connection.transaction { migration.migrate(:up) }
      assert_trigger_contract

      # Record the version with the real migration context after proving the
      # complete up implementation is safe to invoke more than once.
      connection.transaction { migration.migrate(:down) }
      assert_empty installed_trigger_names
      migrate_up!
      assert_trigger_contract
    ensure
      migrate_up!
    end

    private

    def connection
      ActiveRecord::Base.connection
    end

    def tracked_user
      create_user.tap { |record| @users << record }
    end

    def tracked_role
      Role.create!(
        key: "authorization_trigger_#{SecureRandom.hex(6)}",
        name: "Authorization trigger role"
      ).tap { |record| @roles << record }
    end

    def tracked_permission
      Permission.create!(
        key: "identity.authorization_trigger.#{SecureRandom.hex(6)}",
        name: "Authorization trigger permission",
        category: "identity"
      ).tap { |record| @permissions << record }
    end

    def tracked_group
      Community::UserGroup.create!(
        name: "Authorization trigger group #{SecureRandom.hex(5)}",
        permissions: []
      ).tap { |record| @groups << record }
    end

    def assert_single_bump(*users)
      before = users.to_h { |user| [ user.id, permission_version(user) ] }
      yield
      users.each do |user|
        assert_equal before.fetch(user.id) + 1, permission_version(user),
                     "expected one database permission-version bump for user #{user.id}"
      end
    end

    def assert_no_bump(*users)
      before = users.to_h { |user| [ user.id, permission_version(user) ] }
      yield
      users.each do |user|
        assert_equal before.fetch(user.id), permission_version(user),
                     "expected no database permission-version bump for user #{user.id}"
      end
    end

    def permission_version(user)
      User.uncached { User.where(id: user.id).pick(:permission_version) }
    end

    def migration_context
      pool = ActiveRecord::Base.connection_pool
      ActiveRecord::MigrationContext.new(
        Rails.application.config.paths["db/migrate"].to_a,
        ActiveRecord::SchemaMigration.new(pool),
        ActiveRecord::InternalMetadata.new(pool)
      )
    end

    def migrate_down!
      context = migration_context
      context.run(:down, MIGRATION_VERSION) if context.get_all_versions.include?(MIGRATION_VERSION)
      connection.schema_cache.clear!
    end

    def migrate_up!
      context = migration_context
      context.run(:up, MIGRATION_VERSION) unless context.get_all_versions.include?(MIGRATION_VERSION)
      connection.schema_cache.clear!
    end

    def installed_trigger_names
      quoted = EnforceAuthorizationMutationBarrier::TRIGGERS.keys.map do |table|
        connection.quote(table.to_s)
      end.join(", ")
      connection.select_values(<<~SQL.squish)
        SELECT triggers.tgname
          FROM pg_trigger AS triggers
          INNER JOIN pg_class AS tables ON tables.oid = triggers.tgrelid
         WHERE triggers.tgisinternal = FALSE
           AND tables.relname IN (#{quoted})
           AND triggers.tgname LIKE 'identity_auth_%'
         ORDER BY triggers.tgname
      SQL
    end

    def assert_trigger_contract
      expected = TRIGGER_TABLES.values.flatten.sort
      assert_equal expected, installed_trigger_names

      lock_function = connection.select_value(<<~SQL.squish)
        SELECT pg_get_functiondef(functions.oid)
          FROM pg_proc AS functions
         WHERE functions.proname = 'identity_auth_acquire_exclusive_lock'
      SQL
      assert_includes lock_function, EnforceAuthorizationMutationBarrier::LOCK_KEY.to_s
      assert_includes lock_function, "pg_advisory_xact_lock"

      lock_definitions = connection.select_rows(<<~SQL.squish).to_h
        SELECT triggers.tgname, pg_get_triggerdef(triggers.oid)
          FROM pg_trigger AS triggers
         WHERE triggers.tgname IN (
           'identity_auth_user_roles_lock',
           'identity_auth_role_permissions_lock',
           'identity_auth_group_memberships_lock'
         )
      SQL
      assert_includes lock_definitions.fetch("identity_auth_user_roles_lock"),
                      "UPDATE OF user_id, role_id"
      assert_includes lock_definitions.fetch("identity_auth_role_permissions_lock"),
                      "UPDATE OF role_id, permission_id"
      assert_includes lock_definitions.fetch("identity_auth_group_memberships_lock"),
                      "UPDATE OF user_id, community_user_group_id"
    end
  end
end
