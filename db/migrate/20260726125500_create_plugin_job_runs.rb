# frozen_string_literal: true

class CreatePluginJobRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :plugin_job_runs do |t|
      t.string :public_id, null: false, limit: 36
      t.string :owner_plugin_id, null: false, limit: 191
      t.string :plugin_version, null: false, limit: 128
      t.string :job_key, null: false, limit: 191
      t.string :contribution_schema_version, null: false, limit: 32
      t.string :declaration_digest, null: false, limit: 64
      t.jsonb :arguments, null: false, default: {}
      t.string :payload_digest, null: false, limit: 64
      t.string :idempotency_key, null: false, limit: 191
      t.string :status, null: false, limit: 32, default: "queued"
      t.integer :attempts, null: false, default: 0
      t.integer :max_attempts, null: false
      t.integer :retry_wait_seconds, null: false
      t.integer :lease_seconds, null: false
      t.datetime :scheduled_at, null: false
      t.datetime :enqueued_at
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :lease_expires_at
      t.string :active_job_id, limit: 191
      t.string :last_error_code, limit: 64
      t.timestamps
    end

    add_index :plugin_job_runs, :public_id, unique: true
    add_index :plugin_job_runs,
      %i[owner_plugin_id job_key idempotency_key],
      unique: true,
      name: "idx_plugin_job_runs_owner_job_idempotency"
    add_index :plugin_job_runs,
      %i[owner_plugin_id status scheduled_at],
      name: "idx_plugin_job_runs_owner_status_schedule"
    add_index :plugin_job_runs,
      %i[status scheduled_at],
      name: "idx_plugin_job_runs_status_schedule"

    add_check_constraint :plugin_job_runs,
      "status IN ('queued', 'running', 'retrying', 'succeeded', 'failed', 'paused', 'cancelled')",
      name: "plugin_job_runs_status"
    add_check_constraint :plugin_job_runs,
      "attempts >= 0 AND max_attempts BETWEEN 1 AND 10",
      name: "plugin_job_runs_attempt_bounds"
    add_check_constraint :plugin_job_runs,
      "retry_wait_seconds BETWEEN 0 AND 86400",
      name: "plugin_job_runs_retry_wait_bounds"
    add_check_constraint :plugin_job_runs,
      "lease_seconds BETWEEN 30 AND 3600",
      name: "plugin_job_runs_lease_bounds"
    add_check_constraint :plugin_job_runs,
      "declaration_digest ~ '^[0-9a-f]{64}$' AND payload_digest ~ '^[0-9a-f]{64}$'",
      name: "plugin_job_runs_digests"
  end
end
