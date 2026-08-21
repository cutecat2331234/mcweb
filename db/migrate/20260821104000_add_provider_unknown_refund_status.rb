# frozen_string_literal: true

require Rails.root.join("lib/mcweb/migrations/resumable_postgres")

class AddProviderUnknownRefundStatus < ActiveRecord::Migration[8.1]
  include Mcweb::Migrations::ResumablePostgres

  disable_ddl_transaction!

  CONSTRAINT_NAME = "store_refunds_status_valid"
  UP_CONSTRAINT_NAME = "store_refunds_status_with_provider_unknown"
  DOWN_CONSTRAINT_NAME = "store_refunds_status_without_provider_unknown"
  UP_EXPRESSION =
    "status IN ('pending', 'approved', 'provider_unknown', 'rejected', 'failed', 'completed', 'withdrawn')"
  DOWN_EXPRESSION =
    "status IN ('pending', 'approved', 'rejected', 'failed', 'completed', 'withdrawn')"

  def up
    replace_status_constraint!(
      expression: UP_EXPRESSION,
      temporary_name: UP_CONSTRAINT_NAME,
      provider_unknown: true
    )
  end

  def down
    if connection.select_value("SELECT 1 FROM store_refunds WHERE status = 'provider_unknown' LIMIT 1")
      raise ActiveRecord::IrreversibleMigration,
        "resolve provider_unknown refunds before removing the quarantine status"
    end

    replace_status_constraint!(
      expression: DOWN_EXPRESSION,
      temporary_name: DOWN_CONSTRAINT_NAME,
      provider_unknown: false
    )
  end

  private

  def replace_status_constraint!(expression:, temporary_name:, provider_unknown:)
    canonical_definition = constraint_definition(:store_refunds, CONSTRAINT_NAME)
    if canonical_definition && definition_matches?(canonical_definition, provider_unknown: provider_unknown)
      validate_check_constraint :store_refunds, name: CONSTRAINT_NAME unless
        constraint_validated?(:store_refunds, CONSTRAINT_NAME)
      remove_check_constraint :store_refunds, name: temporary_name, if_exists: true
      return
    end

    temporary_definition = constraint_definition(:store_refunds, temporary_name)
    if temporary_definition && !definition_matches?(temporary_definition, provider_unknown: provider_unknown)
      remove_check_constraint :store_refunds, name: temporary_name, if_exists: true
    end

    unless constraint_definition(:store_refunds, temporary_name)
      add_check_constraint :store_refunds,
        expression,
        name: temporary_name,
        validate: false
    end
    validate_check_constraint :store_refunds, name: temporary_name unless
      constraint_validated?(:store_refunds, temporary_name)
    remove_check_constraint :store_refunds, name: CONSTRAINT_NAME, if_exists: true
    rename_constraint(temporary_name, CONSTRAINT_NAME)
  end

  def definition_matches?(definition, provider_unknown:)
    definition.include?("provider_unknown") == provider_unknown
  end

  def rename_constraint(from, to)
    return unless check_constraint_exists?(:store_refunds, name: from)
    return if check_constraint_exists?(:store_refunds, name: to)

    execute <<~SQL.squish
      ALTER TABLE store_refunds
      RENAME CONSTRAINT #{connection.quote_column_name(from)}
      TO #{connection.quote_column_name(to)}
    SQL
  end
end
