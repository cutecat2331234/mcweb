# frozen_string_literal: true

class AddSharedCorePermissions < ActiveRecord::Migration[8.1]
  PERMISSIONS = [
    {
      key: "store.products.read",
      name: "查看商城工作人员通知",
      category: "store",
      description: "接收低库存等仅面向商城工作人员的通知"
    },
    {
      key: "forum.conversations.create",
      name: "分享他人主题到私信",
      category: "forum",
      description: "允许将其他用户创建的论坛主题分享到私密会话"
    },
    {
      key: "identity.groups.read",
      name: "View global identity groups",
      category: "identity",
      description: "View global identity groups and their effective configuration"
    },
    {
      key: "identity.groups.manage",
      name: "Manage global identity groups",
      category: "identity",
      description: "Create, update, and remove global identity groups"
    },
    {
      key: "identity.groups.members.assign",
      name: "Assign global identity-group members",
      category: "identity",
      description: "Add, remove, and select primary global identity-group memberships"
    },
    {
      key: "identity.groups.permissions.manage",
      name: "Manage global identity-group permissions",
      category: "identity",
      description: "Configure the permission keys granted by global identity groups"
    },
    {
      key: "identity.roles.read",
      name: "View global roles",
      category: "identity",
      description: "View global roles and their effective permission grants"
    },
    {
      key: "identity.roles.manage",
      name: "Manage global roles",
      category: "identity",
      description: "Create, update, and remove global roles within the actor's delegation boundary"
    },
    {
      key: "system.bans.manage",
      name: "Manage access bans",
      category: "system",
      description: "Create and remove IP address and email address bans"
    },
    {
      key: "forum.users.trust.manage",
      name: "Manage forum trust levels",
      category: "forum",
      description: "Set or clear a member's forum trust-level override"
    },
    {
      key: "store.credit.adjust",
      name: "Adjust member store credit",
      category: "store",
      description: "Increase or decrease a member's store-credit balance"
    }
  ].freeze

  ALL_PRIVILEGED_ROLE_KEYS = %w[owner super_admin].freeze
  IDENTITY_ROLE_KEYS = %w[owner super_admin forum_admin].freeze
  IDENTITY_GROUP_PERMISSION_KEYS = PERMISSIONS
    .filter_map { |permission| permission[:key] if permission[:key].start_with?("identity.groups.") }
    .freeze
  IDENTITY_ROLE_PERMISSION_KEYS = %w[identity.roles.read identity.roles.manage].freeze
  SYSTEM_BAN_PERMISSION_KEYS = %w[system.bans.manage].freeze
  FORUM_TRUST_ROLE_KEYS = %w[owner super_admin forum_admin].freeze
  STORE_CREDIT_ROLE_KEYS = %w[owner super_admin store_admin finance].freeze
  IDENTITY_PERMISSION_KEYS = (
    IDENTITY_GROUP_PERMISSION_KEYS + IDENTITY_ROLE_PERMISSION_KEYS
  ).freeze

  def up
    PERMISSIONS.each { |attributes| upsert_permission(attributes) }

    grant_identity_permissions_to_legacy_group_manager_roles
    grant_identity_permissions_to_legacy_group_managers
    grant_role_permissions_to_legacy_role_managers
    grant_role_permissions_to_legacy_role_manager_groups
    grant_ban_permissions_to_legacy_system_manager_roles
    grant_ban_permissions_to_legacy_system_managers
    grant_permissions(
      role_keys: FORUM_TRUST_ROLE_KEYS,
      permission_keys: %w[forum.users.trust.manage]
    )
    grant_permissions(
      role_keys: STORE_CREDIT_ROLE_KEYS,
      permission_keys: %w[store.credit.adjust]
    )
    grant_permissions(
      role_keys: ALL_PRIVILEGED_ROLE_KEYS,
      permission_keys: PERMISSIONS.pluck(:key)
    )
    grant_permissions(
      role_keys: IDENTITY_ROLE_KEYS,
      permission_keys: IDENTITY_GROUP_PERMISSION_KEYS
    )
    backfill_staff_identity_module_grants
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "shared permission upserts cannot distinguish pre-existing rows and grants"
  end

  private

  def upsert_permission(attributes)
    execute <<~SQL.squish
      INSERT INTO permissions (key, name, category, description, created_at, updated_at)
      VALUES (
        #{quote(attributes.fetch(:key))},
        #{quote(attributes.fetch(:name))},
        #{quote(attributes.fetch(:category))},
        #{quote(attributes.fetch(:description))},
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      )
      ON CONFLICT (key) DO UPDATE SET
        name = EXCLUDED.name,
        category = EXCLUDED.category,
        description = EXCLUDED.description,
        updated_at = CURRENT_TIMESTAMP
    SQL
  end

  def grant_permissions(role_keys:, permission_keys:)
    execute <<~SQL.squish
      INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
      SELECT roles.id, permissions.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM roles
      CROSS JOIN permissions
      WHERE roles.key IN (#{quoted_list(role_keys)})
        AND permissions.key IN (#{quoted_list(permission_keys)})
      ON CONFLICT (role_id, permission_id) DO NOTHING
    SQL
  end

  def grant_identity_permissions_to_legacy_group_manager_roles
    execute <<~SQL.squish
      INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
      SELECT
        legacy_grants.role_id,
        identity_permissions.id,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM role_permissions AS legacy_grants
      INNER JOIN permissions AS legacy_permissions
        ON legacy_permissions.id = legacy_grants.permission_id
      CROSS JOIN permissions AS identity_permissions
      WHERE legacy_permissions.key = 'forum.sections.manage'
        AND identity_permissions.key IN (#{quoted_list(IDENTITY_GROUP_PERMISSION_KEYS)})
      ON CONFLICT (role_id, permission_id) DO NOTHING
    SQL
  end

  def grant_identity_permissions_to_legacy_group_managers
    execute <<~SQL.squish
      UPDATE community_user_groups
      SET permissions = (
        SELECT COALESCE(jsonb_agg(permission_key ORDER BY permission_key), '[]'::jsonb)
        FROM (
          SELECT DISTINCT existing_permission.value AS permission_key
          FROM jsonb_array_elements_text(community_user_groups.permissions) AS existing_permission
          UNION
          SELECT identity_permission.permission_key
          FROM unnest(ARRAY[#{quoted_list(IDENTITY_GROUP_PERMISSION_KEYS)}]) AS identity_permission(permission_key)
        ) AS effective_permissions
      )
      WHERE permissions @> '["forum.sections.manage"]'::jsonb
    SQL
  end

  def grant_role_permissions_to_legacy_role_managers
    execute <<~SQL.squish
      INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
      SELECT
        legacy_grants.role_id,
        identity_permissions.id,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM role_permissions AS legacy_grants
      INNER JOIN permissions AS legacy_permissions
        ON legacy_permissions.id = legacy_grants.permission_id
      CROSS JOIN permissions AS identity_permissions
      WHERE legacy_permissions.key = 'system.settings.manage'
        AND identity_permissions.key IN (#{quoted_list(IDENTITY_ROLE_PERMISSION_KEYS)})
      ON CONFLICT (role_id, permission_id) DO NOTHING
    SQL
  end

  def grant_ban_permissions_to_legacy_system_manager_roles
    execute <<~SQL.squish
      INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
      SELECT
        legacy_grants.role_id,
        ban_permissions.id,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM role_permissions AS legacy_grants
      INNER JOIN permissions AS legacy_permissions
        ON legacy_permissions.id = legacy_grants.permission_id
      CROSS JOIN permissions AS ban_permissions
      WHERE legacy_permissions.key = 'system.settings.manage'
        AND ban_permissions.key IN (#{quoted_list(SYSTEM_BAN_PERMISSION_KEYS)})
      ON CONFLICT (role_id, permission_id) DO NOTHING
    SQL
  end

  def grant_role_permissions_to_legacy_role_manager_groups
    execute <<~SQL.squish
      UPDATE community_user_groups
      SET permissions = (
        SELECT COALESCE(jsonb_agg(permission_key ORDER BY permission_key), '[]'::jsonb)
        FROM (
          SELECT DISTINCT existing_permission.value AS permission_key
          FROM jsonb_array_elements_text(community_user_groups.permissions) AS existing_permission
          UNION
          SELECT role_permission.permission_key
          FROM unnest(ARRAY[#{quoted_list(IDENTITY_ROLE_PERMISSION_KEYS)}]) AS role_permission(permission_key)
        ) AS effective_permissions
      )
      WHERE permissions @> '["system.settings.manage"]'::jsonb
    SQL
  end

  def grant_ban_permissions_to_legacy_system_managers
    execute <<~SQL.squish
      UPDATE community_user_groups
      SET permissions = (
        SELECT COALESCE(jsonb_agg(permission_key ORDER BY permission_key), '[]'::jsonb)
        FROM (
          SELECT DISTINCT existing_permission.value AS permission_key
          FROM jsonb_array_elements_text(community_user_groups.permissions) AS existing_permission
          UNION
          SELECT ban_permission.permission_key
          FROM unnest(ARRAY[#{quoted_list(SYSTEM_BAN_PERMISSION_KEYS)}]) AS ban_permission(permission_key)
        ) AS effective_permissions
      )
      WHERE permissions @> '["system.settings.manage"]'::jsonb
    SQL
  end

  def backfill_staff_identity_module_grants
    execute <<~SQL.squish
      INSERT INTO admin_module_grants (
        user_id,
        module_key,
        granted_by_id,
        granted_at,
        created_at,
        updated_at
      )
      SELECT
        users.id,
        'identity',
        forum_grants.granted_by_id,
        forum_grants.granted_at,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM users
      INNER JOIN admin_module_grants AS forum_grants
        ON forum_grants.user_id = users.id
        AND forum_grants.module_key = 'forum'
      WHERE users.account_type = 'staff'
        AND EXISTS (
          SELECT 1 FROM user_roles
          INNER JOIN role_permissions ON role_permissions.role_id = user_roles.role_id
          INNER JOIN permissions ON permissions.id = role_permissions.permission_id
          WHERE user_roles.user_id = users.id AND permissions.key = 'identity.groups.manage'
          UNION ALL
          SELECT 1 FROM community_group_memberships
          INNER JOIN community_user_groups
            ON community_user_groups.id = community_group_memberships.community_user_group_id
          WHERE community_group_memberships.user_id = users.id
            AND community_user_groups.permissions @> '["identity.groups.manage"]'::jsonb
        )
      ON CONFLICT (user_id, module_key) DO NOTHING
    SQL
  end

  def quoted_list(values)
    values.map { |value| quote(value) }.join(", ")
  end

  def quote(value)
    connection.quote(value)
  end
end
