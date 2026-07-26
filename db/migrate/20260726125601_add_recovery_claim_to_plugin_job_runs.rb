# frozen_string_literal: true

class AddRecoveryClaimToPluginJobRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :plugin_job_runs, :recovery_claimed_at, :datetime
    add_column :plugin_job_runs, :last_enqueue_error_code, :string, limit: 64
    add_index :plugin_job_runs,
      %i[status recovery_claimed_at],
      name: "idx_plugin_job_runs_status_recovery_claim"
  end
end
