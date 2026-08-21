# frozen_string_literal: true

require Rails.root.join("lib/mcweb/migrations/resumable_postgres")

class EnforceOneActivePaymentPerOrder < ActiveRecord::Migration[8.0]
  include Mcweb::Migrations::ResumablePostgres

  disable_ddl_transaction!

  INDEX_NAME = "idx_payment_records_one_active_per_order"
  ACTIVE_PREDICATE = "status IN ('pending', 'processing')"

  def up
    duplicate_order_ids = connection.select_values(<<~SQL.squish)
      SELECT store_order_id
      FROM payment_records
      WHERE #{ACTIVE_PREDICATE}
      GROUP BY store_order_id
      HAVING COUNT(*) > 1
      ORDER BY store_order_id
      LIMIT 25
    SQL
    if duplicate_order_ids.any?
      raise ActiveRecord::MigrationError,
        "payment_records has multiple active attempts for order ids #{duplicate_order_ids.join(', ')}; " \
        "reconcile their provider sessions before retrying this migration"
    end

    ensure_concurrent_index :payment_records,
      :store_order_id,
      name: INDEX_NAME,
      unique: true,
      where: ACTIVE_PREDICATE
  end

  def down
    remove_concurrent_index :payment_records, name: INDEX_NAME
  end
end
