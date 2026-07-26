# frozen_string_literal: true

class AddPaymentProviderConfigurationManagement < ActiveRecord::Migration[8.1]
  CONFIGURE_PERMISSION = "store.payments.configure"
  CONNECTION_TEST_PERMISSION = "store.payments.connection_test"

  def up
    change_table :payment_provider_configs, bulk: true do |t|
      t.string :mode
      t.datetime :last_connection_tested_at
      t.string :last_connection_test_status
      t.string :last_connection_test_error_code
      t.string :last_connection_test_mode
      t.references :last_connection_tested_by,
        foreign_key: { to_table: :users },
        index: true
    end

    add_check_constraint :payment_provider_configs,
      "mode IS NULL OR mode IN ('test', 'live')",
      name: "payment_provider_configs_mode"
    add_check_constraint :payment_provider_configs,
      "last_connection_test_status IS NULL OR last_connection_test_status IN ('success', 'failed')",
      name: "payment_provider_configs_connection_test_status"
    add_check_constraint :payment_provider_configs,
      "last_connection_test_mode IS NULL OR last_connection_test_mode IN ('test', 'live')",
      name: "payment_provider_configs_connection_test_mode"

    execute <<~SQL.squish
      INSERT INTO payment_provider_configs
        (provider, enabled, settings, created_at, updated_at)
      VALUES
        ('stripe', FALSE, '{}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      ON CONFLICT (provider) DO NOTHING
    SQL

    insert_permission(
      CONFIGURE_PERMISSION,
      "Configure payment providers",
      "Manage encrypted payment-provider credentials, modes, and enabled state"
    )
    insert_permission(
      CONNECTION_TEST_PERMISSION,
      "Test payment-provider connections",
      "Run a confirmed, audited connection test against an enabled payment provider"
    )
    grant_permissions_to_privileged_roles
  end

  def down
    execute <<~SQL.squish
      DELETE FROM role_permissions
      WHERE permission_id IN (
        SELECT id FROM permissions
        WHERE key IN ('#{CONFIGURE_PERMISSION}', '#{CONNECTION_TEST_PERMISSION}')
      )
    SQL
    execute <<~SQL.squish
      DELETE FROM permissions
      WHERE key IN ('#{CONFIGURE_PERMISSION}', '#{CONNECTION_TEST_PERMISSION}')
    SQL

    remove_check_constraint :payment_provider_configs,
      name: "payment_provider_configs_connection_test_mode"
    remove_check_constraint :payment_provider_configs,
      name: "payment_provider_configs_connection_test_status"
    remove_check_constraint :payment_provider_configs,
      name: "payment_provider_configs_mode"

    remove_reference :payment_provider_configs,
      :last_connection_tested_by,
      foreign_key: { to_table: :users }
    remove_columns :payment_provider_configs,
      :mode,
      :last_connection_tested_at,
      :last_connection_test_status,
      :last_connection_test_error_code,
      :last_connection_test_mode
  end

  private

  def insert_permission(key, name, description)
    execute <<~SQL.squish
      INSERT INTO permissions (key, name, category, description, created_at, updated_at)
      VALUES (
        #{connection.quote(key)},
        #{connection.quote(name)},
        'store',
        #{connection.quote(description)},
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      )
      ON CONFLICT (key) DO NOTHING
    SQL
  end

  def grant_permissions_to_privileged_roles
    execute <<~SQL.squish
      INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
      SELECT roles.id, permissions.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM roles
      CROSS JOIN permissions
      WHERE roles.key IN ('owner', 'super_admin')
        AND permissions.key IN ('#{CONFIGURE_PERMISSION}', '#{CONNECTION_TEST_PERMISSION}')
      ON CONFLICT (role_id, permission_id) DO NOTHING
    SQL
  end
end
