# frozen_string_literal: true

class AddPaymentReconciliationRunPermission < ActiveRecord::Migration[8.1]
  PERMISSION_KEY = "store.payments.reconciliation.run"

  def up
    execute <<~SQL.squish
      INSERT INTO permissions (key, name, category, description, created_at, updated_at)
      VALUES (
        #{connection.quote(PERMISSION_KEY)},
        'Run payment reconciliation',
        'store',
        'Queue a confirmed, date-bound Stripe reconciliation run',
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
        AND permissions.key = #{connection.quote(PERMISSION_KEY)}
      ON CONFLICT (role_id, permission_id) DO NOTHING
    SQL
  end

  def down
    execute <<~SQL.squish
      DELETE FROM role_permissions
      WHERE permission_id IN (
        SELECT id FROM permissions WHERE key = #{connection.quote(PERMISSION_KEY)}
      )
    SQL
    execute <<~SQL.squish
      DELETE FROM permissions
      WHERE key = #{connection.quote(PERMISSION_KEY)}
    SQL
  end
end
