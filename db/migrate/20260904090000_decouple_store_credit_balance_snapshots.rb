# frozen_string_literal: true

require Rails.root.join("lib/mcweb/migrations/resumable_postgres")

class DecoupleStoreCreditBalanceSnapshots < ActiveRecord::Migration[8.1]
  include Mcweb::Migrations::ResumablePostgres

  disable_ddl_transaction!

  LEGACY_CONSTRAINT = "chk_store_credit_transactions_adjustment_metadata"
  REQUEST_CONSTRAINT = "chk_store_credit_transactions_request_metadata"
  SNAPSHOT_CONSTRAINT = "chk_store_credit_transactions_balance_snapshot"
  VERSION_CONSTRAINT = "chk_store_credit_transactions_ledger_version"
  AMOUNT_CONSTRAINT = "chk_store_credit_transactions_nonzero_amount"
  BALANCE_PAIR_CONSTRAINT = "chk_store_credit_transactions_balance_pair"
  LEGACY_TEMP_CONSTRAINT = "chk_store_credit_transactions_legacy_metadata"
  LEDGER_INDEX = "idx_store_credit_transactions_user_recorded_id"
  INSERT_UPGRADE_TRIGGER = "store_credit_transactions_upgrade_insert"
  LEDGER_TRIGGER = "store_credit_transactions_append_only"
  LEDGER_FUNCTION = "store_credit_transactions_enforce_append_only"

  LEGACY_LEDGER_VERSION = 1
  CURRENT_LEDGER_VERSION = 2

  REQUEST_EXPRESSION =
    "(request_id IS NULL AND request_fingerprint IS NULL AND authorization_digest IS NULL) OR " \
      "(request_id IS NOT NULL AND request_fingerprint IS NOT NULL AND authorization_digest IS NOT NULL)"
  LEGACY_EXPRESSION =
    "(request_id IS NULL AND request_fingerprint IS NULL AND authorization_digest IS NULL " \
      "AND balance_before_cents IS NULL AND balance_after_cents IS NULL) OR " \
      "(request_id IS NOT NULL AND request_fingerprint IS NOT NULL AND authorization_digest IS NOT NULL " \
      "AND balance_before_cents IS NOT NULL AND balance_after_cents IS NOT NULL)"

  def up
    unless column_exists?(:store_credit_transactions, :ledger_version)
      add_column :store_credit_transactions,
        :ledger_version,
        :integer,
        default: LEGACY_LEDGER_VERSION,
        null: false
    end

    ensure_check_constraint :store_credit_transactions,
      REQUEST_EXPRESSION,
      name: REQUEST_CONSTRAINT
    ensure_check_constraint :store_credit_transactions,
      "(balance_before_cents IS NULL AND balance_after_cents IS NULL) OR " \
        "(balance_before_cents IS NOT NULL AND balance_after_cents IS NOT NULL)",
      name: BALANCE_PAIR_CONSTRAINT
    remove_check_constraint :store_credit_transactions,
      name: LEGACY_CONSTRAINT,
      if_exists: true
    remove_check_constraint :store_credit_transactions,
      name: LEGACY_TEMP_CONSTRAINT,
      if_exists: true

    install_insert_upgrade_guard!
    normalize_existing_versions! unless append_only_trigger_exists?
    promote_insert_guard_to_append_only!

    change_column_default :store_credit_transactions,
      :ledger_version,
      from: LEGACY_LEDGER_VERSION,
      to: CURRENT_LEDGER_VERSION

    ensure_concurrent_index :store_credit_transactions,
      %i[user_id created_at id],
      name: LEDGER_INDEX
    ensure_check_constraint :store_credit_transactions,
      snapshot_expression,
      name: SNAPSHOT_CONSTRAINT
    ensure_check_constraint :store_credit_transactions,
      "ledger_version IN (#{LEGACY_LEDGER_VERSION}, #{CURRENT_LEDGER_VERSION})",
      name: VERSION_CONSTRAINT
    ensure_check_constraint :store_credit_transactions,
      "amount_cents <> 0",
      name: AMOUNT_CONSTRAINT
    remove_check_constraint :store_credit_transactions,
      name: BALANCE_PAIR_CONSTRAINT,
      if_exists: true
    remove_check_constraint :store_credit_transactions,
      name: LEGACY_TEMP_CONSTRAINT,
      if_exists: true
  end

  def down
    if connection.select_value(<<~SQL.squish)
      SELECT 1
      FROM store_credit_transactions
      WHERE request_id IS NULL
        AND (balance_before_cents IS NOT NULL OR balance_after_cents IS NOT NULL)
      LIMIT 1
    SQL
      raise ActiveRecord::IrreversibleMigration,
        "store-credit balance snapshots must be preserved before restoring the legacy metadata constraint"
    end

    legacy_constraint_present = constraint_definition(
      :store_credit_transactions,
      LEGACY_CONSTRAINT
    ).present?
    if legacy_constraint_present
      validate_check_constraint :store_credit_transactions, name: LEGACY_CONSTRAINT unless
        constraint_validated?(:store_credit_transactions, LEGACY_CONSTRAINT)
    else
      ensure_check_constraint :store_credit_transactions,
        LEGACY_EXPRESSION,
        name: LEGACY_TEMP_CONSTRAINT
    end

    connection.transaction do
      drop_append_only_trigger!
      if legacy_constraint_present
        remove_check_constraint :store_credit_transactions,
          name: LEGACY_TEMP_CONSTRAINT,
          if_exists: true
        remove_split_constraints!
      else
        remove_split_constraints!
        rename_constraint(LEGACY_TEMP_CONSTRAINT, LEGACY_CONSTRAINT)
      end
      remove_column :store_credit_transactions, :ledger_version, if_exists: true
    end

    remove_concurrent_index :store_credit_transactions, name: LEDGER_INDEX
  end

  private

  def remove_split_constraints!
    remove_check_constraint :store_credit_transactions,
      name: REQUEST_CONSTRAINT,
      if_exists: true
    remove_check_constraint :store_credit_transactions,
      name: SNAPSHOT_CONSTRAINT,
      if_exists: true
    remove_check_constraint :store_credit_transactions,
      name: VERSION_CONSTRAINT,
      if_exists: true
    remove_check_constraint :store_credit_transactions,
      name: AMOUNT_CONSTRAINT,
      if_exists: true
    remove_check_constraint :store_credit_transactions,
      name: BALANCE_PAIR_CONSTRAINT,
      if_exists: true
  end

  def snapshot_expression
    "(ledger_version = #{LEGACY_LEDGER_VERSION} " \
      "AND balance_before_cents IS NULL AND balance_after_cents IS NULL) OR " \
      "(ledger_version = #{CURRENT_LEDGER_VERSION} " \
      "AND balance_before_cents IS NOT NULL AND balance_after_cents IS NOT NULL " \
      "AND balance_before_cents >= 0 AND balance_after_cents >= 0 " \
      "AND balance_before_cents + amount_cents = balance_after_cents)"
  end

  def install_insert_upgrade_guard!
    execute <<~SQL
      CREATE OR REPLACE FUNCTION #{LEDGER_FUNCTION}()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        current_balance integer;
      BEGIN
        IF TG_OP = 'INSERT' THEN
          IF NEW.balance_before_cents IS NULL AND NEW.balance_after_cents IS NULL THEN
            SELECT store_credit_cents
            INTO current_balance
            FROM users
            WHERE id = NEW.user_id
            FOR KEY SHARE;

            IF NOT FOUND THEN
              RAISE EXCEPTION USING
                ERRCODE = '23503',
                MESSAGE = 'store-credit ledger user does not exist';
            END IF;

            NEW.balance_after_cents := current_balance;
            NEW.balance_before_cents := current_balance - NEW.amount_cents;
          ELSIF NEW.balance_before_cents IS NULL OR NEW.balance_after_cents IS NULL THEN
            RAISE EXCEPTION USING
              ERRCODE = '23514',
              MESSAGE = 'store-credit balance snapshots must be complete';
          END IF;

          NEW.ledger_version := #{CURRENT_LEDGER_VERSION};
          IF NEW.amount_cents = 0 OR
              NEW.balance_before_cents < 0 OR
              NEW.balance_after_cents < 0 OR
              NEW.balance_before_cents + NEW.amount_cents <> NEW.balance_after_cents THEN
            RAISE EXCEPTION USING
              ERRCODE = '23514',
              MESSAGE = 'new store-credit ledger entries must use the current contract';
          END IF;

          RETURN NEW;
        END IF;

        RAISE EXCEPTION USING
          ERRCODE = '23514',
          MESSAGE = 'store-credit ledger entries are append-only';
      END;
      $$;
    SQL

    execute <<~SQL
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1
          FROM pg_trigger
          WHERE tgrelid = 'store_credit_transactions'::regclass
            AND tgname = '#{LEDGER_TRIGGER}'
            AND NOT tgisinternal
        ) AND NOT EXISTS (
          SELECT 1
          FROM pg_trigger
          WHERE tgrelid = 'store_credit_transactions'::regclass
            AND tgname = '#{INSERT_UPGRADE_TRIGGER}'
            AND NOT tgisinternal
        ) THEN
          CREATE TRIGGER #{INSERT_UPGRADE_TRIGGER}
          BEFORE INSERT ON store_credit_transactions
          FOR EACH ROW
          EXECUTE FUNCTION #{LEDGER_FUNCTION}();
        END IF;
      END;
      $$;
    SQL
  end

  def normalize_existing_versions!
    execute <<~SQL.squish
      UPDATE store_credit_transactions
      SET ledger_version = CASE
        WHEN balance_before_cents IS NULL AND balance_after_cents IS NULL
          THEN #{LEGACY_LEDGER_VERSION}
        ELSE #{CURRENT_LEDGER_VERSION}
      END
      WHERE ledger_version IS DISTINCT FROM CASE
        WHEN balance_before_cents IS NULL AND balance_after_cents IS NULL
          THEN #{LEGACY_LEDGER_VERSION}
        ELSE #{CURRENT_LEDGER_VERSION}
      END
    SQL
  end

  def promote_insert_guard_to_append_only!
    execute <<~SQL
      DO $$
      BEGIN
        DROP TRIGGER IF EXISTS #{INSERT_UPGRADE_TRIGGER} ON store_credit_transactions;

        IF NOT EXISTS (
          SELECT 1
          FROM pg_trigger
          WHERE tgrelid = 'store_credit_transactions'::regclass
            AND tgname = '#{LEDGER_TRIGGER}'
            AND NOT tgisinternal
        ) THEN
          CREATE TRIGGER #{LEDGER_TRIGGER}
          BEFORE INSERT OR UPDATE OR DELETE ON store_credit_transactions
          FOR EACH ROW
          EXECUTE FUNCTION #{LEDGER_FUNCTION}();
        END IF;
      END;
      $$;
    SQL
  end

  def append_only_trigger_exists?
    connection.select_value(<<~SQL.squish) == true
      SELECT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'store_credit_transactions'::regclass
          AND tgname = #{connection.quote(LEDGER_TRIGGER)}
          AND NOT tgisinternal
      )
    SQL
  end

  def drop_append_only_trigger!
    execute "DROP TRIGGER IF EXISTS #{INSERT_UPGRADE_TRIGGER} ON store_credit_transactions"
    execute "DROP TRIGGER IF EXISTS #{LEDGER_TRIGGER} ON store_credit_transactions"
    execute "DROP FUNCTION IF EXISTS #{LEDGER_FUNCTION}()"
  end

  def rename_constraint(from, to)
    return if check_constraint_exists?(:store_credit_transactions, name: to)

    execute <<~SQL.squish
      ALTER TABLE store_credit_transactions
      RENAME CONSTRAINT #{connection.quote_column_name(from)}
      TO #{connection.quote_column_name(to)}
    SQL
  end
end
