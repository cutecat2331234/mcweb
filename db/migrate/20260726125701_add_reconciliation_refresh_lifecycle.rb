# frozen_string_literal: true

class AddReconciliationRefreshLifecycle < ActiveRecord::Migration[8.0]
  def up
    add_column :payment_reconciliation_runs,
      :refresh_count,
      :integer,
      null: false,
      default: 0
    add_column :payment_reconciliation_runs, :refresh_started_at, :datetime
    add_check_constraint :payment_reconciliation_runs,
      "refresh_count >= 0",
      name: "payment_recon_runs_refresh_count"

    add_column :payment_reconciliation_discrepancies, :resolved_at, :datetime
    remove_check_constraint :payment_reconciliation_discrepancies,
      name: "payment_recon_discrepancies_status"
    add_check_constraint :payment_reconciliation_discrepancies,
      "status IN ('open', 'acknowledged', 'ignored', 'resolved')",
      name: "payment_recon_discrepancies_status"
  end

  def down
    execute <<~SQL.squish
      UPDATE payment_reconciliation_discrepancies
      SET status = 'open', resolved_at = NULL
      WHERE status = 'resolved'
    SQL

    remove_check_constraint :payment_reconciliation_discrepancies,
      name: "payment_recon_discrepancies_status"
    add_check_constraint :payment_reconciliation_discrepancies,
      "status IN ('open', 'acknowledged', 'ignored')",
      name: "payment_recon_discrepancies_status"
    remove_column :payment_reconciliation_discrepancies, :resolved_at

    remove_check_constraint :payment_reconciliation_runs,
      name: "payment_recon_runs_refresh_count"
    remove_column :payment_reconciliation_runs, :refresh_started_at
    remove_column :payment_reconciliation_runs, :refresh_count
  end
end
