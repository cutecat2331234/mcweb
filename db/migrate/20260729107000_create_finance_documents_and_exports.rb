# frozen_string_literal: true

class CreateFinanceDocumentsAndExports < ActiveRecord::Migration[8.0]
  PERMISSIONS = {
    "store.finance.read" => [
      "View finance records",
      "View tax snapshots, invoices, refund receipts, and finance export status"
    ],
    "store.finance.documents.manage" => [
      "Manage finance documents",
      "Void or create controlled revisions of issued finance documents"
    ],
    "store.finance.exports.create" => [
      "Create finance exports",
      "Request filtered asynchronous finance exports"
    ],
    "store.finance.exports.download" => [
      "Download finance exports",
      "Download completed finance exports before their file expires"
    ]
  }.freeze

  ROLE_GRANTS = {
    "store_admin" => %w[store.finance.read],
    "finance" => PERMISSIONS.keys,
    "owner" => PERMISSIONS.keys,
    "super_admin" => PERMISSIONS.keys
  }.freeze

  def up
    create_table :store_finance_tax_snapshots do |t|
      t.references :store_order, null: false, foreign_key: true, index: false
      t.integer :tax_rate_bps, null: false
      t.integer :taxable_base_cents, null: false
      t.integer :tax_cents, null: false
      t.integer :gross_cents, null: false
      t.string :currency, null: false
      t.string :pricing_mode, null: false, default: "inclusive"
      t.string :rounding_mode, null: false, default: "half_up"
      t.string :jurisdiction_country, null: false
      t.string :jurisdiction_region
      t.string :tax_code, null: false, default: "standard"
      t.integer :calculation_version, null: false, default: 1
      t.string :source_digest, null: false
      t.jsonb :line_snapshot, null: false, default: []
      t.datetime :captured_at, null: false
      t.datetime :retention_until, null: false
      t.timestamps

      t.index :store_order_id, unique: true, name: "idx_finance_tax_snapshots_order"
      t.index %i[jurisdiction_country jurisdiction_region tax_rate_bps],
        name: "idx_finance_tax_snapshots_dimensions"
      t.index :retention_until
      t.check_constraint("tax_rate_bps >= 0 AND tax_rate_bps <= 100000", name: "chk_finance_tax_rate")
      t.check_constraint(
        "taxable_base_cents >= 0 AND tax_cents >= 0 AND gross_cents >= 0",
        name: "chk_finance_tax_amounts"
      )
      t.check_constraint(
        "taxable_base_cents + tax_cents = gross_cents",
        name: "chk_finance_tax_conservation"
      )
      t.check_constraint(
        "pricing_mode = 'inclusive' AND rounding_mode = 'half_up'",
        name: "chk_finance_tax_calculation_contract"
      )
    end

    create_table :store_finance_documents do |t|
      t.string :public_id, null: false
      t.references :store_order, null: false, foreign_key: true
      t.references :store_refund, foreign_key: true
      t.references :store_finance_tax_snapshot,
        null: false,
        foreign_key: true,
        index: { name: "idx_finance_documents_tax_snapshot" }
      t.references :supersedes,
        foreign_key: { to_table: :store_finance_documents },
        index: { name: "idx_finance_documents_supersedes" }
      t.string :document_kind, null: false
      t.string :document_number, null: false
      t.integer :version, null: false, default: 1
      t.string :status, null: false, default: "issued"
      t.string :channel, null: false
      t.string :currency, null: false
      t.integer :net_amount_cents, null: false
      t.integer :tax_amount_cents, null: false
      t.integer :gross_amount_cents, null: false
      t.string :source_digest, null: false
      t.jsonb :content_snapshot, null: false, default: {}
      t.datetime :issued_at, null: false
      t.datetime :superseded_at
      t.datetime :voided_at
      t.datetime :retention_until, null: false
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index :public_id, unique: true
      t.index %i[document_number version], unique: true, name: "idx_finance_documents_number_version"
      t.index %i[store_order_id document_kind version],
        unique: true,
        where: "document_kind = 'invoice'",
        name: "idx_finance_documents_order_kind_version"
      t.index %i[store_refund_id document_kind version],
        unique: true,
        where: "store_refund_id IS NOT NULL",
        name: "idx_finance_documents_refund_kind_version"
      t.index %i[store_order_id document_kind],
        unique: true,
        where: "document_kind = 'invoice' AND status = 'issued'",
        name: "idx_finance_documents_current_invoice"
      t.index %i[store_refund_id document_kind],
        unique: true,
        where: "store_refund_id IS NOT NULL AND document_kind = 'refund_receipt' AND status = 'issued'",
        name: "idx_finance_documents_current_refund"
      t.index %i[document_kind status issued_at], name: "idx_finance_documents_kind_status_time"
      t.index %i[channel currency issued_at], name: "idx_finance_documents_channel_currency"
      t.index :retention_until
      t.check_constraint(
        "document_kind IN ('invoice', 'refund_receipt')",
        name: "chk_finance_documents_kind"
      )
      t.check_constraint(
        "status IN ('issued', 'superseded', 'voided')",
        name: "chk_finance_documents_status"
      )
      t.check_constraint(
        "net_amount_cents >= 0 AND tax_amount_cents >= 0 AND gross_amount_cents >= 0",
        name: "chk_finance_document_amounts"
      )
      t.check_constraint(
        "net_amount_cents + tax_amount_cents = gross_amount_cents",
        name: "chk_finance_document_conservation"
      )
      t.check_constraint(
        "(document_kind = 'invoice' AND store_refund_id IS NULL) OR " \
          "(document_kind = 'refund_receipt' AND store_refund_id IS NOT NULL)",
        name: "chk_finance_document_source"
      )
    end

    create_table :store_finance_document_events do |t|
      t.references :store_finance_document,
        null: false,
        foreign_key: true,
        index: { name: "idx_finance_document_events_document" }
      t.references :actor, foreign_key: { to_table: :users }
      t.string :event_type, null: false
      t.string :request_id
      t.text :reason
      t.jsonb :before_state, null: false, default: {}
      t.jsonb :after_state, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false

      t.index %i[store_finance_document_id created_at],
        name: "idx_finance_document_events_timeline"
      t.index :request_id, unique: true, where: "request_id IS NOT NULL"
      t.check_constraint(
        "event_type IN ('issued', 'superseded', 'voided')",
        name: "chk_finance_document_events_type"
      )
    end

    create_table :store_finance_exports do |t|
      t.string :public_id, null: false
      t.references :requested_by, null: false, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "queued"
      t.string :format, null: false, default: "csv"
      t.string :idempotency_key, null: false
      t.string :filters_digest, null: false
      t.jsonb :filters, null: false, default: {}
      t.integer :progress_percent, null: false, default: 0
      t.integer :row_count
      t.integer :attempts, null: false, default: 0
      t.datetime :requested_at, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :failed_at
      t.datetime :expires_at
      t.datetime :revoked_at
      t.datetime :retention_until, null: false
      t.string :error_code
      t.string :file_sha256
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index :public_id, unique: true
      t.index %i[requested_by_id idempotency_key],
        unique: true,
        name: "idx_finance_exports_request_idempotency"
      t.index %i[requested_by_id status requested_at], name: "idx_finance_exports_actor_status"
      t.index %i[status expires_at], name: "idx_finance_exports_expiry"
      t.index :retention_until
      t.check_constraint(
        "status IN ('queued', 'running', 'completed', 'failed', 'expired', 'revoked')",
        name: "chk_finance_exports_status"
      )
      t.check_constraint(
        "format = 'csv'",
        name: "chk_finance_exports_format"
      )
      t.check_constraint(
        "progress_percent >= 0 AND progress_percent <= 100",
        name: "chk_finance_exports_progress"
      )
      t.check_constraint(
        "attempts >= 0 AND (row_count IS NULL OR row_count >= 0)",
        name: "chk_finance_exports_counts"
      )
    end

    create_table :store_finance_export_events do |t|
      t.references :store_finance_export,
        null: false,
        foreign_key: true,
        index: { name: "idx_finance_export_events_export" }
      t.references :actor, foreign_key: { to_table: :users }
      t.string :status, null: false
      t.integer :progress_percent, null: false
      t.string :request_id
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false

      t.index %i[store_finance_export_id created_at],
        name: "idx_finance_export_events_timeline"
      t.check_constraint(
        "status IN ('queued', 'running', 'completed', 'failed', 'expired', 'revoked')",
        name: "chk_finance_export_events_status"
      )
      t.check_constraint(
        "progress_percent >= 0 AND progress_percent <= 100",
        name: "chk_finance_export_events_progress"
      )
    end

    create_permissions_and_grants
  end

  def down
    delete_permissions_and_grants
    drop_table :store_finance_export_events
    drop_table :store_finance_exports
    drop_table :store_finance_document_events
    drop_table :store_finance_documents
    drop_table :store_finance_tax_snapshots
  end

  private

  def create_permissions_and_grants
    PERMISSIONS.each do |key, (name, description)|
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
        ON CONFLICT (key) DO UPDATE SET
          name = EXCLUDED.name,
          category = EXCLUDED.category,
          description = EXCLUDED.description,
          updated_at = CURRENT_TIMESTAMP
      SQL
    end

    ROLE_GRANTS.each do |role_key, permission_keys|
      execute <<~SQL.squish
        INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
        SELECT roles.id, permissions.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM roles
        CROSS JOIN permissions
        WHERE roles.key = #{connection.quote(role_key)}
          AND permissions.key IN (#{permission_keys.map { |key| connection.quote(key) }.join(', ')})
        ON CONFLICT (role_id, permission_id) DO NOTHING
      SQL
    end
  end

  def delete_permissions_and_grants
    quoted_keys = PERMISSIONS.keys.map { |key| connection.quote(key) }.join(", ")
    execute <<~SQL.squish
      DELETE FROM role_permissions
      WHERE permission_id IN (SELECT id FROM permissions WHERE key IN (#{quoted_keys}))
    SQL
    execute "DELETE FROM permissions WHERE key IN (#{quoted_keys})"
  end
end
