# frozen_string_literal: true

class HardenPaymentWebhookReliability < ActiveRecord::Migration[8.0]
  PERMISSION_KEY = "store.payments.replay"

  def up
    change_table :payment_webhook_events, bulk: true do |t|
      t.integer :attempt_count, null: false, default: 0
      t.integer :retry_count, null: false, default: 0
      t.integer :manual_replay_count, null: false, default: 0
      t.string :payload_digest
      t.string :last_error_code
      t.string :processing_token
      t.datetime :verified_at
      t.datetime :last_attempted_at
      t.datetime :processing_started_at
      t.datetime :next_retry_at
      t.datetime :dead_lettered_at
      t.datetime :last_replayed_at
      t.references :last_replayed_by, foreign_key: { to_table: :users }, index: true
    end

    add_index :payment_webhook_events, %i[status next_retry_at],
      name: "idx_payment_webhooks_status_retry"
    add_index :payment_webhook_events, %i[status processing_started_at],
      name: "idx_payment_webhooks_status_processing"
    add_index :payment_webhook_events, :dead_lettered_at

    execute <<~SQL.squish
      INSERT INTO permissions (key, name, category, description, created_at, updated_at)
      VALUES (
        '#{PERMISSION_KEY}',
        '重放支付 Webhook',
        'store',
        '在支付运维后台人工重放已验证且进入死信的支付 Webhook 事件',
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

    remove_index :payment_webhook_events, :dead_lettered_at
    remove_index :payment_webhook_events, name: "idx_payment_webhooks_status_processing"
    remove_index :payment_webhook_events, name: "idx_payment_webhooks_status_retry"

    remove_reference :payment_webhook_events, :last_replayed_by, foreign_key: { to_table: :users }
    remove_columns :payment_webhook_events,
      :attempt_count,
      :retry_count,
      :manual_replay_count,
      :payload_digest,
      :last_error_code,
      :processing_token,
      :verified_at,
      :last_attempted_at,
      :processing_started_at,
      :next_retry_at,
      :dead_lettered_at,
      :last_replayed_at
  end
end
