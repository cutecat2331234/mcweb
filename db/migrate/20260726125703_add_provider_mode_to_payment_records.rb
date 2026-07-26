# frozen_string_literal: true

class AddProviderModeToPaymentRecords < ActiveRecord::Migration[8.0]
  def up
    add_column :payment_records, :provider_mode, :string

    execute <<~SQL.squish
      UPDATE payment_records
      SET provider_mode = CASE
        WHEN metadata ->> 'stripe_livemode' IN ('true', 'false')
          AND metadata ->> 'stripe_checkout_livemode' IN ('true', 'false')
          AND metadata ->> 'stripe_livemode' =
            metadata ->> 'stripe_checkout_livemode'
          THEN CASE
            WHEN metadata ->> 'stripe_livemode' = 'true' THEN 'live'
            ELSE 'test'
          END
        WHEN metadata ->> 'stripe_livemode' IN ('true', 'false')
          AND NOT (metadata ? 'stripe_checkout_livemode')
          THEN CASE
            WHEN metadata ->> 'stripe_livemode' = 'true' THEN 'live'
            ELSE 'test'
          END
        WHEN metadata ->> 'stripe_checkout_livemode' IN ('true', 'false')
          AND NOT (metadata ? 'stripe_livemode')
          THEN CASE
            WHEN metadata ->> 'stripe_checkout_livemode' = 'true' THEN 'live'
            ELSE 'test'
          END
        ELSE NULL
      END
      WHERE provider = 'stripe'
        AND provider_mode IS NULL
    SQL

    add_check_constraint :payment_records,
      "provider_mode IS NULL OR provider_mode IN ('test', 'live')",
      name: "payment_records_provider_mode"
  end

  def down
    remove_check_constraint :payment_records,
      name: "payment_records_provider_mode"
    remove_column :payment_records, :provider_mode
  end
end
