# frozen_string_literal: true

require Rails.root.join("lib/mcweb/migrations/resumable_postgres")

class AddCustomerOriginToCommerceDisputes < ActiveRecord::Migration[8.1]
  include Mcweb::Migrations::ResumablePostgres

  disable_ddl_transaction!

  CUSTOMER_INDEX = "index_store_disputes_on_customer_opened_by_id"
  UNIQUE_PAYMENT_INDEX = "idx_store_disputes_one_customer_case_per_payment"
  ORIGIN_CHECK = "chk_store_disputes_customer_origin_shape"

  def up
    add_column :store_disputes, :customer_opened_by_id, :bigint,
      if_not_exists: true
    add_column :store_disputes, :customer_opened_at, :datetime,
      if_not_exists: true
    add_column :store_disputes, :customer_withdrawn_at, :datetime,
      if_not_exists: true

    ensure_concurrent_index :store_disputes,
      :customer_opened_by_id,
      name: CUSTOMER_INDEX
    ensure_foreign_key :store_disputes,
      :users,
      column: :customer_opened_by_id
    ensure_customer_case_uniqueness!
    ensure_concurrent_index :store_disputes,
      :payment_record_id,
      name: UNIQUE_PAYMENT_INDEX,
      unique: true,
      where: "customer_opened_by_id IS NOT NULL"
    ensure_check_constraint :store_disputes,
      "(customer_opened_by_id IS NULL AND customer_opened_at IS NULL AND customer_withdrawn_at IS NULL) OR " \
        "(customer_opened_by_id IS NOT NULL AND customer_opened_at IS NOT NULL)",
      name: ORIGIN_CHECK
  end

  def down
    remove_check_constraint :store_disputes,
      name: ORIGIN_CHECK,
      if_exists: true
    remove_concurrent_index :store_disputes, name: UNIQUE_PAYMENT_INDEX
    remove_foreign_key :store_disputes,
      column: :customer_opened_by_id,
      if_exists: true
    remove_concurrent_index :store_disputes, name: CUSTOMER_INDEX
    remove_column :store_disputes, :customer_withdrawn_at, if_exists: true
    remove_column :store_disputes, :customer_opened_at, if_exists: true
    remove_column :store_disputes, :customer_opened_by_id, if_exists: true
  end

  private

  def ensure_customer_case_uniqueness!
    duplicate_payment_ids = connection.select_values(<<~SQL.squish)
      SELECT payment_record_id
      FROM store_disputes
      WHERE customer_opened_by_id IS NOT NULL
      GROUP BY payment_record_id
      HAVING COUNT(*) > 1
      ORDER BY payment_record_id
      LIMIT 25
    SQL
    return if duplicate_payment_ids.empty?

    raise ActiveRecord::MigrationError,
      "store_disputes has multiple customer cases for payment ids " \
      "#{duplicate_payment_ids.join(', ')}; reconcile them before retrying"
  end
end
