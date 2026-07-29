# frozen_string_literal: true

class CreatePluginMaintenanceWindows < ActiveRecord::Migration[8.1]
  def change
    create_table :plugin_maintenance_windows do |t|
      t.string :operation_id, null: false
      t.string :plugin_id
      t.references :actor, foreign_key: { to_table: :users }
      t.boolean :active, null: false, default: true
      t.datetime :started_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :ended_at
      t.timestamps
    end

    add_index :plugin_maintenance_windows, :operation_id, unique: true
    add_index :plugin_maintenance_windows,
              [ :active, :expires_at ],
              name: "index_plugin_maintenance_windows_on_active_and_expiry"
    add_check_constraint(
      :plugin_maintenance_windows,
      "expires_at > started_at",
      name: "plugin_maintenance_windows_valid_interval"
    )
  end
end
