# frozen_string_literal: true

class AddForumSectionLifecyclePermissions < ActiveRecord::Migration[8.1]
  LEGACY_PERMISSION_KEY = "forum.sections.manage"
  DEFAULT_ROLE_KEYS = %w[owner super_admin forum_admin].freeze
  PERMISSIONS = [
    {
      key: "forum.sections.lifecycle",
      name: "Archive and restore forum sections",
      category: "forum",
      description: "Review lifecycle impact, archive active sections, and restore archived sections"
    },
    {
      key: "forum.sections.delete",
      name: "Permanently delete forum sections",
      category: "forum",
      description: "Permanently delete an eligible archived forum section after typed confirmation"
    }
  ].freeze
  PERMISSION_KEYS = PERMISSIONS.pluck(:key).freeze

  def up
    PERMISSIONS.each { |attributes| upsert_permission(attributes) }

    grant_default_roles
    grant_legacy_roles
    grant_legacy_identity_groups
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "forum section lifecycle permission grants cannot be distinguished from later grants"
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
    grant_permissions(<<~SQL.squish)
      roles.key IN (#{quoted_list(DEFAULT_ROLE_KEYS)})
    SQL
  end

  def grant_legacy_roles
    grant_permissions(<<~SQL.squish)
      EXISTS (
        SELECT 1
        FROM role_permissions AS legacy_grants
        INNER JOIN permissions AS legacy_permissions
          ON legacy_permissions.id = legacy_grants.permission_id
        WHERE legacy_grants.role_id = roles.id
          AND legacy_permissions.key = #{quote(LEGACY_PERMISSION_KEY)}
      )
    SQL
  end

  def grant_permissions(role_condition)
    execute <<~SQL.squish
      INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
      SELECT roles.id, permissions.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM roles
      CROSS JOIN permissions
      WHERE #{role_condition}
        AND permissions.key IN (#{quoted_list(PERMISSION_KEYS)})
      ON CONFLICT (role_id, permission_id) DO NOTHING
    SQL
  end

  def grant_legacy_identity_groups
    execute <<~SQL.squish
      UPDATE community_user_groups
      SET permissions = (
        SELECT COALESCE(jsonb_agg(permission_key ORDER BY permission_key), '[]'::jsonb)
        FROM (
          SELECT DISTINCT existing_permission.value AS permission_key
          FROM jsonb_array_elements_text(community_user_groups.permissions) AS existing_permission
          UNION
          SELECT lifecycle_permission.permission_key
          FROM unnest(ARRAY[#{quoted_list(PERMISSION_KEYS)}]) AS lifecycle_permission(permission_key)
        ) AS effective_permissions
      )
      WHERE permissions @> #{quote([ LEGACY_PERMISSION_KEY ].to_json)}::jsonb
    SQL
  end

  def quoted_list(values)
    values.map { |value| quote(value) }.join(", ")
  end

  def quote(value)
    connection.quote(value)
  end
end
