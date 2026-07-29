# frozen_string_literal: true

class CreatePluginRuntimeGenerations < ActiveRecord::Migration[8.1]
  def change
    create_table :plugin_generations do |t|
      t.bigint :number, null: false
      t.string :state, null: false, default: "pending"
      t.string :action, null: false
      t.string :target_plugin_id
      t.string :operation_id
      t.references :initiated_by, foreign_key: { to_table: :users }
      t.references :parent_generation, foreign_key: { to_table: :plugin_generations }
      t.jsonb :desired_plugins, null: false, default: {}
      t.jsonb :previous_plugins, null: false, default: {}
      t.jsonb :expected_process_uids, null: false, default: []
      t.decimal :minimum_ack_ratio, precision: 5, scale: 4, null: false, default: 1
      t.datetime :deadline_at, null: false
      t.datetime :activated_at
      t.datetime :rollback_started_at
      t.datetime :rolled_back_at
      t.string :error_code
      t.text :error_message
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :plugin_generations, :number, unique: true
    add_index :plugin_generations, [ :state, :number ]
    add_index :plugin_generations, :operation_id

    create_table :plugin_process_acks do |t|
      t.references :plugin_generation, null: false, foreign_key: true
      t.string :process_uid, null: false
      t.string :process_kind, null: false
      t.integer :process_pid
      t.string :hostname
      t.string :status, null: false
      t.jsonb :plugin_versions, null: false, default: {}
      t.string :error_code
      t.text :error_message
      t.datetime :acked_at, null: false
      t.datetime :last_seen_at, null: false
      t.timestamps
    end

    add_index :plugin_process_acks,
              [ :plugin_generation_id, :process_uid ],
              unique: true,
              name: "index_plugin_process_acks_on_generation_and_process"
    add_index :plugin_process_acks, [ :process_uid, :last_seen_at ]
    add_index :plugin_process_acks, [ :status, :last_seen_at ]
  end
end
