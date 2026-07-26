# frozen_string_literal: true

class CreatePluginSettingVersions < ActiveRecord::Migration[8.0]
  PERMISSION_KEY = "system.plugins.settings.manage"

  def up
    create_table :plugin_setting_versions do |t|
      t.string :plugin_id, null: false, limit: 191
      t.string :schema_version, null: false, limit: 32
      t.bigint :revision, null: false
      t.string :schema_digest, null: false, limit: 64
      t.text :encrypted_values, null: false
      t.string :change_kind, null: false, limit: 32
      t.references :actor, foreign_key: { to_table: :users }
      t.references :migration_source, foreign_key: { to_table: :plugin_setting_versions }
      t.references :rollback_source, foreign_key: { to_table: :plugin_setting_versions }
      t.timestamps
    end

    add_index :plugin_setting_versions,
      %i[plugin_id schema_version revision],
      unique: true,
      name: "idx_plugin_settings_namespace_version_revision"
    add_index :plugin_setting_versions,
      %i[plugin_id schema_version created_at],
      name: "idx_plugin_settings_namespace_version_created"
    add_check_constraint :plugin_setting_versions,
      "revision > 0",
      name: "plugin_setting_versions_positive_revision"
    add_check_constraint :plugin_setting_versions,
      "change_kind IN ('update', 'migration', 'rollback')",
      name: "plugin_setting_versions_change_kind"
    add_check_constraint :plugin_setting_versions,
      "schema_digest ~ '^[0-9a-f]{64}$'",
      name: "plugin_setting_versions_schema_digest"

    execute <<~SQL.squish
      INSERT INTO permissions (key, name, category, description, created_at, updated_at)
      VALUES (
        '#{PERMISSION_KEY}',
        'Manage plugin settings',
        'system',
        'Read and change schema-managed settings for trusted plugins',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      )
      ON CONFLICT (key) DO NOTHING
    SQL

    execute <<~SQL.squish
      INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
      SELECT roles.id, permissions.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM roles
      CROSS JOIN permissions
      WHERE roles.key IN ('owner', 'super_admin')
        AND permissions.key = '#{PERMISSION_KEY}'
      ON CONFLICT (role_id, permission_id) DO NOTHING
    SQL
  end

  def down
    execute <<~SQL.squish
      DELETE FROM role_permissions
      WHERE permission_id IN (
        SELECT id FROM permissions WHERE key = '#{PERMISSION_KEY}'
      )
    SQL
    execute "DELETE FROM permissions WHERE key = '#{PERMISSION_KEY}'"

    drop_table :plugin_setting_versions
  end
end
