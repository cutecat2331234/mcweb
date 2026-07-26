# frozen_string_literal: true

class IndexPaymentProviderMode < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_index :payment_records,
      %i[provider provider_mode status created_at id],
      name: "idx_payment_records_reconciliation_mode",
      algorithm: :concurrently,
      if_not_exists: true

    execute <<~SQL.squish
      CREATE INDEX CONCURRENTLY IF NOT EXISTS
        idx_payment_records_on_mode_stripe_pi
      ON payment_records (
        provider,
        provider_mode,
        ((metadata ->> 'stripe_payment_intent_id'))
      )
      WHERE (metadata ->> 'stripe_payment_intent_id') IS NOT NULL
    SQL
  end

  def down
    execute <<~SQL.squish
      DROP INDEX CONCURRENTLY IF EXISTS
        idx_payment_records_on_mode_stripe_pi
    SQL
    remove_index :payment_records,
      name: "idx_payment_records_reconciliation_mode",
      algorithm: :concurrently,
      if_exists: true
  end
end
