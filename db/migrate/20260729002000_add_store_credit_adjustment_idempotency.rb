# frozen_string_literal: true

class AddStoreCreditAdjustmentIdempotency < ActiveRecord::Migration[8.1]
  def change
    change_table :store_credit_transactions, bulk: true do |t|
      t.string :request_id, limit: 36
      t.string :request_fingerprint, limit: 64
      t.string :authorization_digest, limit: 64
      t.integer :balance_before_cents
      t.integer :balance_after_cents
    end

    add_index :store_credit_transactions,
      :request_id,
      unique: true,
      where: "request_id IS NOT NULL",
      name: "idx_store_credit_transactions_request_id"
    add_index :store_credit_transactions,
      :authorization_digest,
      unique: true,
      where: "authorization_digest IS NOT NULL",
      name: "idx_store_credit_transactions_authorization"

    add_check_constraint :store_credit_transactions,
      "request_id IS NULL OR request_id ~ " \
        "'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'",
      name: "chk_store_credit_transactions_request_id"
    add_check_constraint :store_credit_transactions,
      "(request_id IS NULL AND request_fingerprint IS NULL AND authorization_digest IS NULL " \
        "AND balance_before_cents IS NULL AND balance_after_cents IS NULL) OR " \
        "(request_id IS NOT NULL AND request_fingerprint IS NOT NULL AND authorization_digest IS NOT NULL " \
        "AND balance_before_cents IS NOT NULL AND balance_after_cents IS NOT NULL)",
      name: "chk_store_credit_transactions_adjustment_metadata"
    add_check_constraint :store_credit_transactions,
      "request_fingerprint IS NULL OR request_fingerprint ~ '^[0-9a-f]{64}$'",
      name: "chk_store_credit_transactions_request_fingerprint"
    add_check_constraint :store_credit_transactions,
      "authorization_digest IS NULL OR authorization_digest ~ '^[0-9a-f]{64}$'",
      name: "chk_store_credit_transactions_authorization_digest"
  end
end
