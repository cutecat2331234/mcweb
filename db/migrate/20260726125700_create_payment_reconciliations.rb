# frozen_string_literal: true

class CreatePaymentReconciliations < ActiveRecord::Migration[8.0]
  READ_PERMISSION = "store.payments.reconciliation.read"
  REVIEW_PERMISSION = "store.payments.reconciliation.review"

  def up
    create_table :payment_reconciliation_runs do |t|
      t.string :provider, null: false
      t.string :mode, null: false
      t.datetime :window_start, null: false
      t.datetime :window_end, null: false
      t.string :status, null: false, default: "pending"
      t.string :phase, null: false, default: "payments"
      t.string :payment_cursor
      t.string :refund_cursor
      t.string :processing_token
      t.string :failure_code
      t.integer :attempt_count, null: false, default: 0
      t.integer :payments_checked, null: false, default: 0
      t.integer :refunds_checked, null: false, default: 0
      t.integer :discrepancies_count, null: false, default: 0
      t.datetime :started_at
      t.datetime :last_heartbeat_at
      t.datetime :failed_at
      t.datetime :completed_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :payment_reconciliation_runs,
      %i[provider mode window_start window_end],
      unique: true,
      name: "idx_payment_recon_runs_window"
    add_index :payment_reconciliation_runs,
      %i[status last_heartbeat_at],
      name: "idx_payment_recon_runs_recovery"
    add_check_constraint :payment_reconciliation_runs,
      "window_end > window_start",
      name: "payment_recon_runs_window"
    add_check_constraint :payment_reconciliation_runs,
      "status IN ('pending', 'running', 'completed', 'failed', 'skipped')",
      name: "payment_recon_runs_status"
    add_check_constraint :payment_reconciliation_runs,
      "phase IN ('payments', 'refunds', 'local_checks', 'completed')",
      name: "payment_recon_runs_phase"
    add_check_constraint :payment_reconciliation_runs,
      "mode IN ('test', 'live')",
      name: "payment_recon_runs_mode"
    add_check_constraint :payment_reconciliation_runs,
      "attempt_count >= 0 AND payments_checked >= 0 AND refunds_checked >= 0 AND discrepancies_count >= 0",
      name: "payment_recon_runs_counters"

    create_table :payment_reconciliation_observations do |t|
      t.references :run,
        null: false,
        foreign_key: { to_table: :payment_reconciliation_runs },
        index: false
      t.string :subject_type, null: false
      t.string :reference_digest, null: false
      t.timestamps
    end

    add_index :payment_reconciliation_observations,
      %i[run_id subject_type reference_digest],
      unique: true,
      name: "idx_payment_recon_observations_unique"
    add_check_constraint :payment_reconciliation_observations,
      "subject_type IN ('payment', 'refund')",
      name: "payment_recon_observations_subject"

    create_table :payment_reconciliation_discrepancies do |t|
      t.references :run,
        null: false,
        foreign_key: { to_table: :payment_reconciliation_runs },
        index: false
      t.references :payment_record, foreign_key: true
      t.references :refund, foreign_key: { to_table: :store_refunds }
      t.references :store_order, foreign_key: true
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.string :public_id, null: false
      t.string :provider, null: false
      t.string :mode, null: false
      t.string :subject_type, null: false
      t.string :kind, null: false
      t.string :reference_masked
      t.string :reference_digest, null: false
      t.string :fingerprint, null: false
      t.string :status, null: false, default: "open"
      t.string :local_status
      t.string :provider_status
      t.integer :local_amount_cents
      t.integer :provider_amount_cents
      t.string :local_currency
      t.string :provider_currency
      t.text :review_note
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :reviewed_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :payment_reconciliation_discrepancies,
      :fingerprint,
      unique: true,
      name: "idx_payment_recon_discrepancies_fingerprint"
    add_index :payment_reconciliation_discrepancies,
      :public_id,
      unique: true,
      name: "idx_payment_recon_discrepancies_public_id"
    add_index :payment_reconciliation_discrepancies,
      %i[status created_at],
      name: "idx_payment_recon_discrepancies_status"
    add_index :payment_reconciliation_discrepancies,
      %i[provider subject_type kind],
      name: "idx_payment_recon_discrepancies_filters"
    add_index :payment_reconciliation_discrepancies,
      %i[run_id status],
      name: "idx_payment_recon_discrepancies_run"
    add_check_constraint :payment_reconciliation_discrepancies,
      "status IN ('open', 'acknowledged', 'ignored')",
      name: "payment_recon_discrepancies_status"
    add_check_constraint :payment_reconciliation_discrepancies,
      "subject_type IN ('payment', 'refund')",
      name: "payment_recon_discrepancies_subject"
    add_check_constraint :payment_reconciliation_discrepancies,
      "mode IN ('test', 'live')",
      name: "payment_recon_discrepancies_mode"
    add_check_constraint :payment_reconciliation_discrepancies,
      "(local_amount_cents IS NULL OR local_amount_cents >= 0) AND (provider_amount_cents IS NULL OR provider_amount_cents >= 0)",
      name: "payment_recon_discrepancies_amounts"

    add_permission!(
      READ_PERMISSION,
      "View payment reconciliation",
      "View daily payment and refund reconciliation runs and discrepancies"
    )
    add_permission!(
      REVIEW_PERMISSION,
      "Review payment reconciliation discrepancies",
      "Acknowledge or ignore reconciliation discrepancies without changing financial records"
    )
  end

  def down
    remove_permission!(REVIEW_PERMISSION)
    remove_permission!(READ_PERMISSION)

    drop_table :payment_reconciliation_discrepancies
    drop_table :payment_reconciliation_observations
    drop_table :payment_reconciliation_runs
  end

  private

  def add_permission!(key, name, description)
    execute <<~SQL.squish
      INSERT INTO permissions (key, name, category, description, created_at, updated_at)
      VALUES (
        #{connection.quote(key)},
        #{connection.quote(name)},
        'store',
        #{connection.quote(description)},
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
        AND permissions.key = #{connection.quote(key)}
      ON CONFLICT (role_id, permission_id) DO NOTHING
    SQL
  end

  def remove_permission!(key)
    execute <<~SQL.squish
      DELETE FROM role_permissions
      WHERE permission_id IN (
        SELECT id FROM permissions WHERE key = #{connection.quote(key)}
      )
    SQL
    execute "DELETE FROM permissions WHERE key = #{connection.quote(key)}"
  end
end
