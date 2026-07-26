# frozen_string_literal: true

class CreatePaymentLatePaymentCases < ActiveRecord::Migration[8.0]
  PERMISSION_KEY = "store.payments.late_review"

  def up
    create_table :payment_late_payment_cases do |t|
      t.references :payment_record, null: false, foreign_key: true, index: { unique: true }
      t.references :payment_webhook_event, null: false, foreign_key: true, index: { unique: true }
      t.references :store_order, null: false, foreign_key: true
      t.references :acknowledged_by, foreign_key: { to_table: :users }
      t.string :provider, null: false
      t.string :reason, null: false
      t.string :status, null: false, default: "open"
      t.string :disposition
      t.integer :amount_cents, null: false
      t.string :currency, null: false
      t.text :review_note
      t.datetime :acknowledged_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :payment_late_payment_cases, %i[status created_at],
      name: "idx_late_payment_cases_status_created"
    add_index :payment_late_payment_cases, %i[provider status],
      name: "idx_late_payment_cases_provider_status"
    add_index :payment_late_payment_cases, %i[reason status],
      name: "idx_late_payment_cases_reason_status"

    execute <<~SQL.squish
      INSERT INTO permissions (key, name, category, description, created_at, updated_at)
      VALUES (
        '#{PERMISSION_KEY}',
        'Review late payments',
        'store',
        'View and acknowledge paid provider events that cannot be applied to a local order',
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

    drop_table :payment_late_payment_cases
  end
end
