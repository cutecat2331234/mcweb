class CreateDataGovernance < ActiveRecord::Migration[8.0]
  def change
    create_table :identity_data_exports do |t|
      t.references :user, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :status, null: false, default: "queued"
      t.string :format, null: false, default: "zip"
      t.string :idempotency_key, null: false
      t.integer :attempts, null: false, default: 0
      t.datetime :requested_at, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :failed_at
      t.datetime :revoked_at
      t.datetime :expires_at
      t.string :error_code
      t.jsonb :manifest, null: false, default: {}
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index :public_id, unique: true
      t.index %i[user_id idempotency_key], unique: true, name: "idx_identity_exports_idempotency"
      t.index %i[user_id status requested_at], name: "idx_identity_exports_user_status"
      t.check_constraint(
        "status IN ('queued', 'running', 'completed', 'failed', 'revoked', 'expired')",
        name: "chk_identity_data_exports_status"
      )
    end

    create_table :data_retention_policies do |t|
      t.string :resource_type, null: false
      t.integer :retention_days
      t.boolean :user_deletable, null: false, default: true
      t.boolean :moderator_restorable, null: false, default: true
      t.boolean :legal_hold_supported, null: false, default: true
      t.text :notes
      t.timestamps

      t.index :resource_type, unique: true
    end

    create_table :data_retention_holds do |t|
      t.references :target, polymorphic: true, null: false
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :released_by, foreign_key: { to_table: :users }
      t.string :public_id, null: false
      t.string :status, null: false, default: "active"
      t.text :reason, null: false
      t.string :policy_reference
      t.datetime :expires_at
      t.datetime :released_at
      t.text :release_reason
      t.timestamps

      t.index :public_id, unique: true
      t.index %i[target_type target_id status], name: "idx_retention_holds_target_status"
      t.check_constraint(
        "status IN ('active', 'released')",
        name: "chk_data_retention_holds_status"
      )
    end

    add_column :users, :account_closure_outcome, :string
    add_column :users, :account_closed_at, :datetime
    add_index :users, :account_closure_outcome
  end
end
