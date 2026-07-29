# frozen_string_literal: true

class AddPluginLifecyclePermissions < ActiveRecord::Migration[8.1]
  PERMISSIONS = {
    "system.plugins.view" => [
      "View plugins",
      "View installed plugins, contributions and package state"
    ],
    "system.plugins.install" => [
      "Install and upgrade plugins",
      "Install reviewed packages and upgrade an installed plugin"
    ],
    "system.plugins.enable" => [
      "Enable plugins",
      "Enable a disabled plugin package"
    ],
    "system.plugins.disable" => [
      "Disable plugins",
      "Disable an active plugin package"
    ],
    "system.plugins.diagnostics" => [
      "View plugin diagnostics",
      "Inspect file health, lifecycle runs and process generations"
    ],
    "system.plugins.recover" => [
      "Recover plugins",
      "Restore a verified package from its recovery point"
    ],
    "system.plugins.rollback" => [
      "Roll back plugins",
      "Request a plugin release or runtime generation rollback"
    ],
    "system.plugins.uninstall_preserve" => [
      "Uninstall plugins and preserve data",
      "Remove plugin code while retaining plugin-owned data"
    ],
    "system.plugins.uninstall_purge" => [
      "Uninstall plugins and purge data",
      "Run trusted teardown and purge plugin-owned data during uninstall"
    ]
  }.freeze

  def up
    PERMISSIONS.each do |key, (name, description)|
      execute <<~SQL.squish
        INSERT INTO permissions (key, name, category, description, created_at, updated_at)
        VALUES (
          #{connection.quote(key)},
          #{connection.quote(name)},
          'system',
          #{connection.quote(description)},
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        )
        ON CONFLICT (key) DO NOTHING
      SQL
    end

    PERMISSIONS.each_key do |new_key|
      execute <<~SQL.squish
        INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
        SELECT role_permissions.role_id, new_permission.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM role_permissions
        INNER JOIN permissions legacy_permission
          ON legacy_permission.id = role_permissions.permission_id
        CROSS JOIN permissions new_permission
        WHERE legacy_permission.key = 'system.plugins.manage'
          AND new_permission.key = #{connection.quote(new_key)}
        ON CONFLICT (role_id, permission_id) DO NOTHING
      SQL
    end
  end

  def down
    quoted_keys = PERMISSIONS.keys.map { |key| connection.quote(key) }.join(", ")
    execute <<~SQL.squish
      DELETE FROM role_permissions
      WHERE permission_id IN (SELECT id FROM permissions WHERE key IN (#{quoted_keys}))
    SQL
    execute <<~SQL.squish
      DELETE FROM permissions WHERE key IN (#{quoted_keys})
    SQL
  end
end
