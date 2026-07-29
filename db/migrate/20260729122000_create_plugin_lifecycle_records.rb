# frozen_string_literal: true

class CreatePluginLifecycleRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :plugin_installations do |t|
      t.string :plugin_id, null: false
      t.string :current_version
      t.string :desired_state, null: false, default: "disabled"
      t.string :current_state, null: false, default: "uploaded"
      t.string :edition, null: false, default: "ce"
      t.bigint :active_generation_number
      t.string :last_operation_id
      t.string :error_code
      t.text :error_message
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :plugin_installations, :plugin_id, unique: true
    add_index :plugin_installations, [ :current_state, :updated_at ]
    add_index :plugin_installations, :last_operation_id

    create_table :plugin_lifecycle_runs do |t|
      t.string :operation_id, null: false
      t.references :plugin_installation, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :plugin_id
      t.string :action, null: false
      t.string :state, null: false, default: "running"
      t.string :from_version
      t.string :to_version
      t.bigint :generation_number
      t.boolean :dry_run, null: false, default: false
      t.boolean :maintenance_mode, null: false, default: false
      t.boolean :retryable, null: false, default: true
      t.string :error_code
      t.text :error_message
      t.string :recovery_path
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.timestamps
    end

    add_index :plugin_lifecycle_runs, :operation_id, unique: true
    add_index :plugin_lifecycle_runs, [ :plugin_id, :started_at ]
    add_index :plugin_lifecycle_runs, [ :state, :started_at ]

    create_table :plugin_lifecycle_steps do |t|
      t.references :plugin_lifecycle_run, null: false, foreign_key: true
      t.integer :sequence, null: false
      t.string :step_key, null: false
      t.string :state, null: false
      t.string :idempotency_key, null: false
      t.boolean :retryable, null: false, default: true
      t.jsonb :details, null: false, default: {}
      t.string :error_code
      t.text :error_message
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.timestamps
    end

    add_index :plugin_lifecycle_steps,
              [ :plugin_lifecycle_run_id, :sequence ],
              unique: true,
              name: "index_plugin_lifecycle_steps_on_run_and_sequence"
    add_index :plugin_lifecycle_steps,
              [ :plugin_lifecycle_run_id, :idempotency_key ],
              unique: true,
              name: "index_plugin_lifecycle_steps_on_run_and_idempotency"
    add_index :plugin_lifecycle_steps, [ :state, :started_at ]
  end
end
