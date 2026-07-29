# frozen_string_literal: true

class CreateCommerceDisputes < ActiveRecord::Migration[8.0]
  PERMISSIONS = {
    "store.disputes.read" => [
      "View payment disputes",
      "View dispute deadlines, states, ownership, and safe order context"
    ],
    "store.disputes.sensitive_read" => [
      "View sensitive dispute details",
      "View payment references, evidence content, and financial exposure details"
    ],
    "store.disputes.assign" => [
      "Assign payment disputes",
      "Assign or reassign a dispute owner with an immutable reason"
    ],
    "store.disputes.note" => [
      "Add payment dispute notes",
      "Add immutable internal notes to a payment dispute timeline"
    ],
    "store.disputes.evidence_submit" => [
      "Submit payment dispute evidence",
      "Create and submit retained evidence packages for payment disputes"
    ],
    "store.disputes.accept_loss" => [
      "Accept payment dispute losses",
      "Accept a dispute loss after a signed impact preview"
    ],
    "store.disputes.close" => [
      "Close payment disputes",
      "Close terminal disputes and start their retention period"
    ],
    "store.disputes.rights_manage" => [
      "Manage disputed-order rights",
      "Freeze, revoke, or restore entitlements linked to disputed orders"
    ]
  }.freeze

  LEGACY_GRANTS = {
    "store.disputes.read" => "store.orders.read",
    "store.disputes.sensitive_read" => "store.orders.refund",
    "store.disputes.assign" => "store.orders.read",
    "store.disputes.note" => "store.orders.read",
    "store.disputes.evidence_submit" => "store.orders.refund",
    "store.disputes.accept_loss" => "store.orders.refund",
    "store.disputes.close" => "store.orders.refund",
    "store.disputes.rights_manage" => "store.orders.refund"
  }.freeze

  def up
    create_table :store_disputes do |t|
      t.string :public_id, null: false
      t.references :store_order, null: false, foreign_key: true
      t.references :payment_record, null: false, foreign_key: true
      t.references :assigned_to, foreign_key: { to_table: :users }
      t.references :accepted_loss_by, foreign_key: { to_table: :users }
      t.references :closed_by, foreign_key: { to_table: :users }
      t.string :provider, null: false
      t.string :provider_dispute_id, null: false
      t.string :kind, null: false, default: "dispute"
      t.string :status, null: false, default: "open"
      t.string :provider_status
      t.string :risk_level, null: false, default: "high"
      t.string :reason_code
      t.string :resolution
      t.string :rights_status, null: false, default: "unchanged"
      t.integer :amount_cents, null: false
      t.integer :liability_cents, null: false, default: 0
      t.integer :offset_cents, null: false, default: 0
      t.string :currency, null: false
      t.datetime :evidence_due_at
      t.datetime :latest_provider_event_at
      t.bigint :latest_provider_sequence
      t.string :latest_provider_event_id
      t.datetime :accepted_loss_at
      t.datetime :closed_at
      t.datetime :retention_until
      t.boolean :legal_hold, null: false, default: false
      t.jsonb :metadata, null: false, default: {}
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index :public_id, unique: true
      t.index %i[provider provider_dispute_id], unique: true, name: "idx_store_disputes_provider_identity"
      t.index %i[status evidence_due_at], name: "idx_store_disputes_status_due"
      t.index %i[risk_level status], name: "idx_store_disputes_risk_status"
      t.index %i[assigned_to_id status], name: "idx_store_disputes_assignee_status"
      t.index %i[retention_until legal_hold], name: "idx_store_disputes_retention"
      t.check_constraint(
        "kind IN ('dispute', 'chargeback')",
        name: "chk_store_disputes_kind"
      )
      t.check_constraint(
        "status IN ('open', 'evidence_required', 'evidence_submitted', 'under_review', 'won', 'lost', 'withdrawn', 'closed')",
        name: "chk_store_disputes_status"
      )
      t.check_constraint(
        "risk_level IN ('low', 'medium', 'high', 'critical')",
        name: "chk_store_disputes_risk"
      )
      t.check_constraint(
        "rights_status IN ('unchanged', 'frozen', 'revoked', 'restored')",
        name: "chk_store_disputes_rights_status"
      )
      t.check_constraint(
        "resolution IS NULL OR resolution IN ('won', 'lost', 'withdrawn', 'accepted_loss')",
        name: "chk_store_disputes_resolution"
      )
      t.check_constraint(
        "amount_cents > 0 AND liability_cents >= 0 AND offset_cents >= 0 AND liability_cents + offset_cents = amount_cents",
        name: "chk_store_disputes_amount_conservation"
      )
    end

    create_table :store_dispute_events do |t|
      t.references :store_dispute, null: false, foreign_key: true
      t.references :payment_webhook_event, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :idempotency_key, null: false
      t.string :request_id
      t.string :source, null: false
      t.string :event_type, null: false
      t.string :provider_event_id
      t.string :provider_status
      t.string :from_status
      t.string :to_status
      t.datetime :provider_occurred_at
      t.bigint :provider_sequence
      t.string :payload_digest, limit: 64
      t.text :note
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false

      t.index :idempotency_key, unique: true
      t.index :request_id
      t.index %i[store_dispute_id created_at], name: "idx_store_dispute_events_timeline"
      t.index :provider_event_id
      t.check_constraint(
        "source IN ('channel', 'manual', 'policy', 'system')",
        name: "chk_store_dispute_events_source"
      )
      t.check_constraint(
        "payload_digest IS NULL OR payload_digest ~ '^[0-9a-f]{64}$'",
        name: "chk_store_dispute_events_digest"
      )
    end

    create_table :store_dispute_evidence do |t|
      t.string :public_id, null: false
      t.references :store_dispute, null: false, foreign_key: true
      t.references :submitted_by, null: false, foreign_key: { to_table: :users }
      t.string :idempotency_key, null: false
      t.string :title, null: false
      t.string :filename, null: false
      t.string :content_type, null: false, default: "text/plain"
      t.text :content
      t.integer :byte_size, null: false
      t.string :sha256, null: false, limit: 64
      t.string :submission_status, null: false, default: "submitted"
      t.string :provider_reference
      t.datetime :submitted_at, null: false
      t.datetime :retention_until
      t.datetime :purged_at
      t.timestamps

      t.index :public_id, unique: true
      t.index :idempotency_key, unique: true
      t.index %i[retention_until purged_at], name: "idx_store_dispute_evidence_retention"
      t.check_constraint("byte_size >= 0", name: "chk_store_dispute_evidence_size")
      t.check_constraint(
        "sha256 ~ '^[0-9a-f]{64}$'",
        name: "chk_store_dispute_evidence_digest"
      )
      t.check_constraint(
        "submission_status IN ('submitted', 'failed', 'purged')",
        name: "chk_store_dispute_evidence_status"
      )
    end

    create_table :store_dispute_rights_actions do |t|
      t.references :store_dispute, null: false, foreign_key: true
      t.references :subject, polymorphic: true, null: false
      t.references :actor, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.string :idempotency_key, null: false
      t.text :reason
      t.jsonb :before_state, null: false, default: {}
      t.jsonb :after_state, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false

      t.index :idempotency_key, unique: true
      t.index %i[store_dispute_id subject_type subject_id],
              name: "idx_store_dispute_rights_subject"
      t.check_constraint(
        "action IN ('freeze', 'revoke', 'restore')",
        name: "chk_store_dispute_rights_action"
      )
    end

    add_reference :store_user_entitlements,
                  :risk_hold_dispute,
                  foreign_key: { to_table: :store_disputes }
    add_column :store_user_entitlements, :risk_held_at, :datetime
    add_index :store_user_entitlements, :risk_held_at

    add_reference :store_user_memberships,
                  :risk_hold_dispute,
                  foreign_key: { to_table: :store_disputes }
    add_column :store_user_memberships, :risk_held_at, :datetime
    add_index :store_user_memberships, :risk_held_at

    insert_permissions!
  end

  def down
    remove_dispute_permissions!
    remove_index :store_user_memberships, :risk_held_at
    remove_column :store_user_memberships, :risk_held_at
    remove_reference :store_user_memberships,
                     :risk_hold_dispute,
                     foreign_key: { to_table: :store_disputes }
    remove_index :store_user_entitlements, :risk_held_at
    remove_column :store_user_entitlements, :risk_held_at
    remove_reference :store_user_entitlements,
                     :risk_hold_dispute,
                     foreign_key: { to_table: :store_disputes }
    drop_table :store_dispute_rights_actions
    drop_table :store_dispute_evidence
    drop_table :store_dispute_events
    drop_table :store_disputes
  end

  private

  def insert_permissions!
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
        ON CONFLICT (key) DO NOTHING
      SQL
    end

    LEGACY_GRANTS.each do |new_key, legacy_key|
      execute <<~SQL.squish
        INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
        SELECT role_permissions.role_id, new_permission.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM role_permissions
        INNER JOIN permissions legacy_permission
          ON legacy_permission.id = role_permissions.permission_id
        CROSS JOIN permissions new_permission
        WHERE legacy_permission.key = #{connection.quote(legacy_key)}
          AND new_permission.key = #{connection.quote(new_key)}
        ON CONFLICT (role_id, permission_id) DO NOTHING
      SQL
    end
  end

  def remove_dispute_permissions!
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
