# frozen_string_literal: true

class CreateStoreHighRiskOperations < ActiveRecord::Migration[8.1]
  def change
    create_table :store_high_risk_operations do |t|
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.references :target_user, foreign_key: { to_table: :users }
      t.string :action, null: false, limit: 64
      t.string :request_id, null: false, limit: 36
      t.string :request_fingerprint, null: false, limit: 64
      t.string :authorization_digest, null: false, limit: 64
      t.string :resource_type
      t.bigint :resource_id
      t.string :resource_public_id
      t.text :reason, null: false
      t.jsonb :target_snapshot, null: false, default: {}
      t.jsonb :before_state, null: false, default: {}
      t.jsonb :after_state, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :store_high_risk_operations, :request_id,
      unique: true,
      name: "idx_store_high_risk_operations_request"
    add_index :store_high_risk_operations, :authorization_digest,
      unique: true,
      name: "idx_store_high_risk_operations_authorization"
    add_index :store_high_risk_operations, :request_fingerprint,
      name: "idx_store_high_risk_operations_fingerprint"
    add_index :store_high_risk_operations, :action
    add_index :store_high_risk_operations, %i[resource_type resource_id],
      name: "idx_store_high_risk_operations_resource"

    add_check_constraint :store_high_risk_operations,
      "request_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'",
      name: "chk_store_high_risk_operations_request_id"
    add_check_constraint :store_high_risk_operations,
      "request_fingerprint ~ '^[0-9a-f]{64}$'",
      name: "chk_store_high_risk_operations_fingerprint"
    add_check_constraint :store_high_risk_operations,
      "authorization_digest ~ '^[0-9a-f]{64}$'",
      name: "chk_store_high_risk_operations_authorization"
  end
end
