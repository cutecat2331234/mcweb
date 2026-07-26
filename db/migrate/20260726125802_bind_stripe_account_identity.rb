# frozen_string_literal: true

class BindStripeAccountIdentity < ActiveRecord::Migration[8.1]
  def up
    change_table :payment_provider_configs, bulk: true do |table|
      table.string :account_fingerprint, limit: 64
      table.string :last_connection_test_credential_revision, limit: 64
    end

    # A pre-identity connection test cannot prove which Stripe account was
    # tested. Force one new test instead of treating that legacy result as
    # checkout-ready.
    execute <<~SQL.squish
      UPDATE payment_provider_configs
      SET
        last_connection_tested_at = NULL,
        last_connection_test_status = NULL,
        last_connection_test_error_code = NULL,
        last_connection_test_mode = NULL,
        last_connection_tested_by_id = NULL
      WHERE provider = 'stripe'
        AND last_connection_test_status = 'success'
    SQL

    add_check_constraint :payment_provider_configs,
      "account_fingerprint IS NULL OR account_fingerprint ~ '^[0-9a-f]{64}$'",
      name: "payment_provider_configs_account_fingerprint"
    add_check_constraint :payment_provider_configs,
      "last_connection_test_credential_revision IS NULL " \
        "OR last_connection_test_credential_revision ~ '^[0-9a-f]{64}$'",
      name: "payment_provider_configs_test_credential_revision"
    add_check_constraint :payment_provider_configs,
      "last_connection_test_status IS DISTINCT FROM 'success' " \
        "OR (account_fingerprint IS NOT NULL " \
        "AND last_connection_test_credential_revision IS NOT NULL)",
      name: "payment_provider_configs_success_identity"
  end

  def down
    remove_check_constraint :payment_provider_configs,
      name: "payment_provider_configs_success_identity"
    remove_check_constraint :payment_provider_configs,
      name: "payment_provider_configs_test_credential_revision"
    remove_check_constraint :payment_provider_configs,
      name: "payment_provider_configs_account_fingerprint"

    remove_columns :payment_provider_configs,
      :last_connection_test_credential_revision,
      :account_fingerprint
  end
end
