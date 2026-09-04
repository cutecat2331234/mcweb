# frozen_string_literal: true

require "test_helper"

class StoreCreditBalanceSnapshotMigrationContractTest < ActiveSupport::TestCase
  MIGRATION_PATH = Rails.root.join(
    "db/migrate/20260904090000_decouple_store_credit_balance_snapshots.rb",
  )

  test "roll-forward versions the ledger and installs database append-only enforcement" do
    source = MIGRATION_PATH.read.gsub("\r\n", "\n")
    up_source = source.split("  def up\n", 2).last&.split("\n  def down\n", 2)&.first

    assert_not_nil up_source

    request_constraint = up_source.index("name: REQUEST_CONSTRAINT")
    balance_pair_constraint = up_source.index("name: BALANCE_PAIR_CONSTRAINT")
    snapshot_constraint = up_source.index("name: SNAPSHOT_CONSTRAINT")
    legacy_constraint = up_source.index("name: LEGACY_CONSTRAINT")
    legacy_temp_constraint = up_source.index("name: LEGACY_TEMP_CONSTRAINT")
    insert_guard = up_source.index("install_insert_upgrade_guard!")
    normalization = up_source.index("normalize_existing_versions!")
    append_only_promotion = up_source.index("promote_insert_guard_to_append_only!")
    current_default = up_source.index("change_column_default")

    assert_not_nil request_constraint
    assert_not_nil balance_pair_constraint
    assert_not_nil snapshot_constraint
    assert_not_nil legacy_constraint
    assert_not_nil legacy_temp_constraint
    assert_not_nil insert_guard
    assert_not_nil normalization
    assert_not_nil append_only_promotion
    assert_not_nil current_default
    assert_operator legacy_constraint, :>, balance_pair_constraint
    assert_operator insert_guard, :>, legacy_constraint
    assert_operator normalization, :>, insert_guard
    assert_operator append_only_promotion, :>, normalization
    assert_operator current_default, :>, append_only_promotion
    assert_operator snapshot_constraint, :>, current_default

    temporary_cleanup = up_source.byteslice(legacy_temp_constraint, 100)
    assert_includes temporary_cleanup, "if_exists: true"

    assert_includes source, "LEGACY_LEDGER_VERSION = 1"
    assert_includes source, "CURRENT_LEDGER_VERSION = 2"
    assert_includes source, "ledger_version IN"
    assert_includes source, "balance_before_cents + amount_cents = balance_after_cents"
    assert_includes source, "NEW.balance_after_cents := current_balance"
    assert_includes source, "NEW.balance_before_cents := current_balance - NEW.amount_cents"
    assert_includes source, "NEW.ledger_version := \#{CURRENT_LEDGER_VERSION}"
    assert_includes source, "FOR KEY SHARE"
    assert_includes source, "normalize_existing_versions! unless append_only_trigger_exists?"
    assert_includes source, "BEFORE INSERT OR UPDATE OR DELETE ON store_credit_transactions"
    assert_includes source, "new store-credit ledger entries must use the current contract"
    assert_includes source, "store-credit ledger entries are append-only"
  end

  test "rollback validates its legacy contract before atomically removing append-only protection" do
    source = MIGRATION_PATH.read.gsub("\r\n", "\n")
    down_source = source.split("  def down\n", 2).last&.split("\n  private\n", 2)&.first

    assert_not_nil down_source

    legacy_preflight = down_source.index("legacy_constraint_present =")
    legacy_validation = down_source.index("ensure_check_constraint :store_credit_transactions")
    atomic_transition = down_source.index("connection.transaction do")
    trigger_removal = down_source.index("drop_append_only_trigger!")
    index_removal = down_source.index("remove_concurrent_index")

    assert_not_nil legacy_preflight
    assert_not_nil legacy_validation
    assert_not_nil atomic_transition
    assert_not_nil trigger_removal
    assert_not_nil index_removal
    assert_operator legacy_validation, :>, legacy_preflight
    assert_operator atomic_transition, :>, legacy_validation
    assert_operator trigger_removal, :>, atomic_transition
    assert_operator index_removal, :>, trigger_removal
  end
end
