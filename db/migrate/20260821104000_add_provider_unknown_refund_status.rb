# frozen_string_literal: true

class AddProviderUnknownRefundStatus < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  CONSTRAINT_NAME = "store_refunds_status_valid"
  UP_CONSTRAINT_NAME = "store_refunds_status_with_provider_unknown"
  DOWN_CONSTRAINT_NAME = "store_refunds_status_without_provider_unknown"
  UP_EXPRESSION =
    "status IN ('pending', 'approved', 'provider_unknown', 'rejected', 'failed', 'completed', 'withdrawn')"
  DOWN_EXPRESSION =
    "status IN ('pending', 'approved', 'rejected', 'failed', 'completed', 'withdrawn')"

  def up
    add_check_constraint :store_refunds,
      UP_EXPRESSION,
      name: UP_CONSTRAINT_NAME,
      validate: false
    validate_check_constraint :store_refunds, name: UP_CONSTRAINT_NAME
    remove_check_constraint :store_refunds, name: CONSTRAINT_NAME
    rename_constraint(UP_CONSTRAINT_NAME, CONSTRAINT_NAME)
  end

  def down
    if select_value("SELECT 1 FROM store_refunds WHERE status = 'provider_unknown' LIMIT 1")
      raise ActiveRecord::IrreversibleMigration,
        "resolve provider_unknown refunds before removing the quarantine status"
    end

    add_check_constraint :store_refunds,
      DOWN_EXPRESSION,
      name: DOWN_CONSTRAINT_NAME,
      validate: false
    validate_check_constraint :store_refunds, name: DOWN_CONSTRAINT_NAME
    remove_check_constraint :store_refunds, name: CONSTRAINT_NAME
    rename_constraint(DOWN_CONSTRAINT_NAME, CONSTRAINT_NAME)
  end

  private

  def rename_constraint(from, to)
    execute <<~SQL.squish
      ALTER TABLE store_refunds
      RENAME CONSTRAINT #{connection.quote_column_name(from)}
      TO #{connection.quote_column_name(to)}
    SQL
  end
end
