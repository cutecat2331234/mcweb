# frozen_string_literal: true

class CreateMinecraftNodeOperations < ActiveRecord::Migration[8.0]
  ACTIVE_BATCH_STATUSES = %w[dispatched running result_pending_ack].freeze

  def change
    create_table :minecraft_node_operations do |t|
      t.string :public_id, null: false
      t.string :operation_type, null: false
      t.string :status, null: false, default: "queued"
      t.string :idempotency_key
      t.string :request_digest, null: false
      t.jsonb :request_payload, null: false, default: {}
      t.jsonb :result, null: false, default: {}
      t.integer :target_count, null: false, default: 0
      t.integer :batch_count, null: false, default: 0
      t.integer :completed_target_count, null: false, default: 0
      t.integer :failed_target_count, null: false, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :minecraft_node_operations, :public_id, unique: true
    add_index :minecraft_node_operations, :idempotency_key,
      unique: true,
      where: "idempotency_key IS NOT NULL"
    add_index :minecraft_node_operations, %i[status created_at]

    create_table :minecraft_node_operation_batches do |t|
      t.references :minecraft_node_operation,
        null: false,
        foreign_key: true,
        index: { name: "idx_minecraft_node_batches_operation" }
      t.references :minecraft_node,
        null: false,
        foreign_key: true,
        index: { name: "idx_minecraft_node_batches_node" }
      t.string :public_id, null: false
      t.string :delivery_id, null: false
      t.string :status, null: false, default: "ready"
      t.jsonb :payload, null: false, default: {}
      t.string :payload_digest, null: false
      t.string :result_digest
      t.string :acknowledgement_id
      t.jsonb :result, null: false, default: {}
      t.integer :target_count, null: false, default: 0
      t.integer :completed_target_count, null: false, default: 0
      t.integer :failed_target_count, null: false, default: 0
      t.integer :delivery_attempts, null: false, default: 0
      t.datetime :claimed_at
      t.datetime :started_at
      t.datetime :lease_expires_at
      t.datetime :result_recorded_at
      t.datetime :acknowledged_at
      t.datetime :completed_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :minecraft_node_operation_batches, :public_id,
      unique: true,
      name: "idx_minecraft_node_batches_public_id"
    add_index :minecraft_node_operation_batches, :delivery_id,
      unique: true,
      name: "idx_minecraft_node_batches_delivery_id"
    add_index :minecraft_node_operation_batches, :acknowledgement_id,
      unique: true,
      where: "acknowledgement_id IS NOT NULL",
      name: "idx_minecraft_node_batches_ack_id"
    add_index :minecraft_node_operation_batches,
      %i[minecraft_node_operation_id minecraft_node_id],
      unique: true,
      name: "idx_minecraft_node_batches_operation_node"
    add_index :minecraft_node_operation_batches,
      %i[minecraft_node_id status created_at],
      name: "idx_minecraft_node_batches_dispatch"
    add_index :minecraft_node_operation_batches,
      :minecraft_node_id,
      unique: true,
      where: "status IN (#{ACTIVE_BATCH_STATUSES.map { |status| quote(status) }.join(', ')})",
      name: "idx_minecraft_node_batches_one_active"

    create_table :minecraft_node_operation_target_results do |t|
      t.references :minecraft_node_operation_batch,
        null: false,
        foreign_key: true,
        index: { name: "idx_minecraft_node_target_results_batch" }
      t.references :minecraft_server,
        foreign_key: true,
        index: { name: "idx_minecraft_node_target_results_server" }
      t.string :target_key, null: false
      t.string :status, null: false
      t.string :expected_revision
      t.string :applied_revision
      t.jsonb :result, null: false, default: {}
      t.string :error_code
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :applied_at
      t.timestamps
    end

    add_index :minecraft_node_operation_target_results,
      %i[minecraft_node_operation_batch_id target_key],
      unique: true,
      name: "idx_minecraft_node_target_results_unique"
  end
end
