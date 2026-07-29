# frozen_string_literal: true

class CreateOperationsWorkerHeartbeats < ActiveRecord::Migration[8.1]
  def change
    create_table :operations_worker_heartbeats do |t|
      t.string :process_ref, null: false
      t.string :process_kind, null: false, default: "sidekiq"
      t.datetime :started_at, null: false
      t.datetime :last_seen_at, null: false
      t.timestamps
    end

    add_index :operations_worker_heartbeats, :process_ref, unique: true
    add_index :operations_worker_heartbeats,
              [ :process_kind, :last_seen_at ],
              name: "idx_operations_worker_heartbeats_freshness"
    add_check_constraint :operations_worker_heartbeats,
                         "process_kind IN ('sidekiq')",
                         name: "operations_worker_heartbeats_kind"
  end
end
