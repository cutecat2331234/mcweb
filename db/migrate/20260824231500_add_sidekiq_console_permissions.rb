# frozen_string_literal: true

class AddSidekiqConsolePermissions < ActiveRecord::Migration[8.1]
  DEFAULT_ROLE_KEYS = %w[owner super_admin].freeze
  PERMISSIONS = [
    {
      key: "system.sidekiq.read",
      name: "View Sidekiq console",
      category: "system",
      description: "View native Sidekiq queue, retry, schedule, and worker diagnostics"
    },
    {
      key: "system.sidekiq.manage",
      name: "Manage Sidekiq console",
      category: "system",
      description: "Run native Sidekiq retry, delete, queue, schedule, and worker actions"
    }
  ].freeze
  PERMISSION_KEYS = PERMISSIONS.pluck(:key).freeze
  LEGACY_ROLE_MAPPINGS = [
    [ "system.jobs.read", "system.sidekiq.read" ],
    [ "system.jobs.manage", "system.sidekiq.read" ],
    [ "system.jobs.manage", "system.sidekiq.manage" ]
  ].freeze

  def up
    PERMISSIONS.each { |attributes| upsert_permission(attributes) }
    grant_default_roles
    grant_legacy_roles
    grant_legacy_identity_groups
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Sidekiq console permission grants cannot be distinguished from later grants"
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

  def grant_default_roles
    execute <<~SQL.squish
      INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
      SELECT roles.id, permissions.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM roles
      CROSS JOIN permissions
      WHERE roles.key IN (#{quoted_list(DEFAULT_ROLE_KEYS)})
        AND permissions.key IN (#{quoted_list(PERMISSION_KEYS)})
      ON CONFLICT (role_id, permission_id) DO NOTHING
    SQL
  end

  def grant_legacy_roles
    mappings = LEGACY_ROLE_MAPPINGS
      .map { |legacy, sidekiq| "(#{quote(legacy)}, #{quote(sidekiq)})" }
      .join(", ")
    execute <<~SQL.squish
      WITH permission_mappings (legacy_key, sidekiq_key) AS (
        VALUES #{mappings}
      )
      INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
      SELECT DISTINCT
        legacy_grants.role_id,
        sidekiq_permissions.id,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM permission_mappings
      INNER JOIN permissions AS legacy_permissions
        ON legacy_permissions.key = permission_mappings.legacy_key
      INNER JOIN role_permissions AS legacy_grants
        ON legacy_grants.permission_id = legacy_permissions.id
      INNER JOIN permissions AS sidekiq_permissions
        ON sidekiq_permissions.key = permission_mappings.sidekiq_key
      ON CONFLICT (role_id, permission_id) DO NOTHING
    SQL
  end

  def grant_legacy_identity_groups
    execute <<~SQL.squish
      UPDATE community_user_groups AS groups
      SET permissions = (
        SELECT COALESCE(
          jsonb_agg(permission_key ORDER BY permission_key),
          '[]'::jsonb
        )
        FROM (
          SELECT DISTINCT existing_permission.value AS permission_key
          FROM jsonb_array_elements_text(groups.permissions) AS existing_permission
          UNION
          SELECT 'system.sidekiq.read'
          WHERE groups.permissions ?| ARRAY['system.jobs.read', 'system.jobs.manage']
          UNION
          SELECT 'system.sidekiq.manage'
          WHERE groups.permissions ? 'system.jobs.manage'
        ) AS effective_permissions
      )
      WHERE groups.permissions ?| ARRAY['system.jobs.read', 'system.jobs.manage']
    SQL
  end

  def quoted_list(values)
    values.map { |value| quote(value) }.join(", ")
  end

  def quote(value)
    connection.quote(value)
  end
end
