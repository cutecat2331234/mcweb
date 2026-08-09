# frozen_string_literal: true

class CreateOperationsManualTaskRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :operations_manual_task_runs do |t|
      t.references :requested_by, foreign_key: { to_table: :users }
      t.string :task_key, null: false
      t.string :status, null: false, default: "queued"
      t.string :job_id
      t.string :idempotency_key, null: false
      t.jsonb :arguments, null: false, default: {}
      t.jsonb :result, null: false, default: {}
      t.string :error_code
      t.text :error_message
      t.datetime :requested_at, null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :operations_manual_task_runs,
              [ :task_key, :idempotency_key ],
              unique: true,
              name: "idx_operations_manual_tasks_idempotency"
    add_index :operations_manual_task_runs,
              [ :status, :requested_at ],
              name: "idx_operations_manual_tasks_status"
    add_check_constraint :operations_manual_task_runs,
                         "status IN ('queued', 'running', 'succeeded', 'failed')",
                         name: "operations_manual_task_runs_status"
    add_check_constraint :operations_manual_task_runs,
                         "((status IN ('queued', 'running') AND finished_at IS NULL) OR " \
                         "(status IN ('succeeded', 'failed') AND finished_at IS NOT NULL))",
                         name: "operations_manual_task_runs_finished_shape"
  end
end
