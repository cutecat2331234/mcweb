# frozen_string_literal: true

class AddSystemPluginsManagePermission < ActiveRecord::Migration[8.0]
  PERMISSION_KEY = "system.plugins.manage"

  def up
    execute <<~SQL.squish
      INSERT INTO permissions (key, name, category, description, created_at, updated_at)
      VALUES (
        '#{PERMISSION_KEY}',
        '管理插件包',
        'system',
        '安装、升级、启用、禁用和卸载受信任的插件包',
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
  end
end
