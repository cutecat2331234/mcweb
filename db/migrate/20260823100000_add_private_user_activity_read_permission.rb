# frozen_string_literal: true

class AddPrivateUserActivityReadPermission < ActiveRecord::Migration[8.1]
  PERMISSION_KEY = "identity.users.private_activity.read"
  PRIVILEGED_ROLE_KEYS = %w[owner super_admin].freeze

  def up
    execute <<~SQL.squish
      INSERT INTO permissions (key, name, category, description, created_at, updated_at)
      VALUES (
        #{connection.quote(PERMISSION_KEY)},
        'View private member activity',
        'identity',
        'View private presence, commerce, points, check-in, and game-activity details',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      )
      ON CONFLICT (key) DO UPDATE SET
        name = EXCLUDED.name,
        category = EXCLUDED.category,
        description = EXCLUDED.description,
        updated_at = CURRENT_TIMESTAMP
    SQL

    execute <<~SQL.squish
      INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
      SELECT roles.id, permissions.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM roles
      CROSS JOIN permissions
      WHERE roles.key IN (#{quoted_role_keys})
        AND permissions.key = #{connection.quote(PERMISSION_KEY)}
      ON CONFLICT (role_id, permission_id) DO NOTHING
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "private member activity grants may have changed after this migration"
  end

  private

  def quoted_role_keys
    PRIVILEGED_ROLE_KEYS.map { |key| connection.quote(key) }.join(", ")
  end
end
