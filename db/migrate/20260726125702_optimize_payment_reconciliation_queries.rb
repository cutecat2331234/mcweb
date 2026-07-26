# frozen_string_literal: true

class OptimizePaymentReconciliationQueries < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    execute <<~SQL.squish
      CREATE INDEX CONCURRENTLY IF NOT EXISTS
        idx_payment_records_on_provider_stripe_pi
      ON payment_records (
        provider,
        ((metadata ->> 'stripe_payment_intent_id'))
      )
      WHERE (metadata ->> 'stripe_payment_intent_id') IS NOT NULL
    SQL

    add_index :payment_records,
      %i[provider status created_at id],
      name: "idx_payment_records_reconciliation_local",
      algorithm: :concurrently,
      if_not_exists: true
    add_index :store_refunds,
      %i[status created_at payment_record_id id],
      name: "idx_store_refunds_reconciliation_local",
      algorithm: :concurrently,
      if_not_exists: true
    add_index :payment_reconciliation_observations,
      %i[subject_type reference_digest run_id],
      name: "idx_payment_recon_observations_lookup",
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :payment_reconciliation_observations,
      name: "idx_payment_recon_observations_lookup",
      algorithm: :concurrently,
      if_exists: true
    remove_index :store_refunds,
      name: "idx_store_refunds_reconciliation_local",
      algorithm: :concurrently,
      if_exists: true
    remove_index :payment_records,
      name: "idx_payment_records_reconciliation_local",
      algorithm: :concurrently,
      if_exists: true
    execute <<~SQL.squish
      DROP INDEX CONCURRENTLY IF EXISTS
        idx_payment_records_on_provider_stripe_pi
    SQL
  end
end
