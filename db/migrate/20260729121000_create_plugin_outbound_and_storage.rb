# frozen_string_literal: true

class CreatePluginOutboundAndStorage < ActiveRecord::Migration[8.1]
  def change
    create_table :plugin_outbound_deliveries do |t|
      t.string :public_id, null: false
      t.string :owner_plugin_id, null: false
      t.string :kind, null: false
      t.string :idempotency_key, null: false
      t.string :status, null: false, default: "queued"
      t.references :user, foreign_key: true
      t.text :encrypted_destination
      t.text :encrypted_payload, null: false
      t.text :encrypted_secret
      t.string :payload_digest, null: false
      t.integer :attempts, null: false, default: 0
      t.integer :max_attempts, null: false, default: 5
      t.datetime :next_attempt_at
      t.integer :last_http_status
      t.string :last_error_code
      t.text :response_summary
      t.datetime :delivered_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :plugin_outbound_deliveries, :public_id, unique: true
    add_index :plugin_outbound_deliveries,
              [ :owner_plugin_id, :kind, :idempotency_key ],
              unique: true,
              name: "index_plugin_deliveries_on_owner_kind_idempotency"
    add_index :plugin_outbound_deliveries, [ :status, :next_attempt_at ]

    create_table :plugin_storage_objects do |t|
      t.string :public_id, null: false
      t.string :owner_plugin_id, null: false
      t.string :key, null: false, limit: 512
      t.string :content_type, null: false
      t.bigint :byte_size, null: false
      t.string :checksum_sha256, null: false
      t.text :encrypted_metadata, null: false
      t.datetime :expires_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :plugin_storage_objects, :public_id, unique: true
    add_index :plugin_storage_objects,
              [ :owner_plugin_id, :key ],
              unique: true
    add_index :plugin_storage_objects, :expires_at
  end
end
