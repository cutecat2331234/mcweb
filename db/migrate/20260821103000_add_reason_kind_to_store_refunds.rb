# frozen_string_literal: true

require Rails.root.join("lib/mcweb/migrations/resumable_postgres")

class AddReasonKindToStoreRefunds < ActiveRecord::Migration[8.1]
  include Mcweb::Migrations::ResumablePostgres

  disable_ddl_transaction!

  BATCH_SIZE = 500
  BACKFILL_LEDGER = "store_refund_reason_kind_backfills"
  CONSTRAINT_NAME = "store_refunds_reason_kind_valid"
  CONSTRAINT_EXPRESSION =
    "reason_kind IS NULL OR " \
      "reason_kind IN ('customer_request', 'admin_refund', 'superseded_by_admin_refund')"
  LEGACY_REASON_KINDS = {
    "customer_request" => [ "Customer request", "客户申请" ],
    "admin_refund" => [ "Admin refund", "后台退款" ],
    "superseded_by_admin_refund" => [ "Superseded by admin refund", "已被后台退款取代" ]
  }.freeze

  def up
    add_column :store_refunds, :reason_kind, :string, if_not_exists: true
    ensure_backfill_ledger!
    existing_constraint = constraint_definition(:store_refunds, CONSTRAINT_NAME)
    if existing_constraint&.include?("reason IS NULL")
      remove_check_constraint :store_refunds, name: CONSTRAINT_NAME, if_exists: true
    end
    ensure_check_constraint :store_refunds,
      CONSTRAINT_EXPRESSION,
      name: CONSTRAINT_NAME

    LEGACY_REASON_KINDS.each do |kind, reasons|
      backfill_reason_kind!(
        kind,
        reasons,
        all_customer_requests: kind == "customer_request"
      )
    end
  end

  def down
    if column_exists?(:store_refunds, :reason_kind)
      restore_ledger_values! if table_exists?(BACKFILL_LEDGER)
      LEGACY_REASON_KINDS.each do |kind, reasons|
        restore_new_reason_kind_values!(kind, reasons.first)
      end
    end

    remove_check_constraint :store_refunds, name: CONSTRAINT_NAME, if_exists: true
    remove_column :store_refunds, :reason_kind, if_exists: true
    drop_table BACKFILL_LEDGER, if_exists: true
  end

  private

  def ensure_backfill_ledger!
    create_table BACKFILL_LEDGER, id: false, if_not_exists: true do |table|
      table.bigint :store_refund_id, null: false, primary_key: true
      table.text :legacy_reason
    end
    legacy_reason_column = connection.columns(BACKFILL_LEDGER).find { |column| column.name == "legacy_reason" }
    change_column_null BACKFILL_LEDGER, :legacy_reason, true if legacy_reason_column && !legacy_reason_column.null
  end

  def backfill_reason_kind!(kind, reasons, all_customer_requests: false)
    quoted_reasons = reasons.map { |reason| connection.quote(reason) }.join(", ")
    request_scope = case kind
    when "customer_request" then "AND refund.requested_by_customer = TRUE"
    when "admin_refund" then "AND refund.requested_by_customer = FALSE"
    else ""
    end
    reason_scope = all_customer_requests ? "" : "AND refund.reason IN (#{quoted_reasons})"

    loop do
      changed = connection.transaction(requires_new: true) do
        rows = connection.select_rows(<<~SQL.squish)
          SELECT refund.id, refund.reason
          FROM store_refunds refund
          WHERE refund.reason_kind IS NULL
            #{reason_scope}
            #{request_scope}
          ORDER BY refund.id
          LIMIT #{BATCH_SIZE}
          FOR UPDATE
        SQL
        next 0 if rows.empty?

        backup_values = rows.map do |id, legacy_reason|
          "(#{Integer(id)}, #{connection.quote(legacy_reason)})"
        end.join(", ")
        connection.execute(<<~SQL.squish)
          INSERT INTO #{connection.quote_table_name(BACKFILL_LEDGER)}
            (store_refund_id, legacy_reason)
          VALUES #{backup_values}
          ON CONFLICT (store_refund_id) DO NOTHING
        SQL
        ids = rows.map { |id, _reason| Integer(id) }.join(", ")
        connection.execute(<<~SQL.squish)
          UPDATE store_refunds
          SET reason_kind = #{connection.quote(kind)},
              reason = CASE
                WHEN reason IN (#{quoted_reasons}) THEN NULL
                ELSE reason
              END
          WHERE id IN (#{ids})
            AND reason_kind IS NULL
        SQL
        rows.length
      end
      break if changed.zero?
    end
  end

  def restore_ledger_values!
    loop do
      changed = connection.transaction(requires_new: true) do
        rows = connection.select_rows(<<~SQL.squish)
          SELECT refund.id, backup.legacy_reason
          FROM store_refunds refund
          INNER JOIN #{connection.quote_table_name(BACKFILL_LEDGER)} backup
            ON backup.store_refund_id = refund.id
          WHERE refund.reason_kind IS NOT NULL
          ORDER BY refund.id
          LIMIT #{BATCH_SIZE}
          FOR UPDATE OF refund
        SQL
        next 0 if rows.empty?

        values = rows.map do |id, legacy_reason|
          "(#{Integer(id)}, #{connection.quote(legacy_reason)}::text)"
        end.join(", ")
        connection.execute(<<~SQL.squish)
          UPDATE store_refunds refund
          SET reason = restored.legacy_reason, reason_kind = NULL
          FROM (VALUES #{values}) AS restored(id, legacy_reason)
          WHERE refund.id = restored.id
        SQL
        rows.length
      end
      break if changed.zero?
    end
  end

  def restore_new_reason_kind_values!(kind, fallback_reason)
    loop do
      changed = connection.transaction(requires_new: true) do
        ids = connection.select_values(<<~SQL.squish).map { |id| Integer(id) }
          SELECT refund.id
          FROM store_refunds refund
          WHERE refund.reason_kind = #{connection.quote(kind)}
          ORDER BY refund.id
          LIMIT #{BATCH_SIZE}
          FOR UPDATE
        SQL
        next 0 if ids.empty?

        connection.execute(<<~SQL.squish)
          UPDATE store_refunds
          SET reason = COALESCE(reason, #{connection.quote(fallback_reason)}),
              reason_kind = NULL
          WHERE id IN (#{ids.join(', ')})
        SQL
        ids.length
      end
      break if changed.zero?
    end
  end
end
