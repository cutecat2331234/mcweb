# frozen_string_literal: true

class CreateForumPointAccountsAndTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :forum_point_accounts do |t|
      t.bigint :user_id, null: false
      t.integer :balance, null: false, default: 0
      t.string :currency, null: false, default: "points"
      t.timestamps
    end

    add_index :forum_point_accounts, [ :user_id, :currency ], unique: true,
              name: "idx_forum_point_accounts_user_currency"
    add_index :forum_point_accounts, :currency
    add_foreign_key :forum_point_accounts, :users

    create_table :forum_point_transactions do |t|
      t.bigint :forum_point_account_id, null: false
      t.bigint :user_id, null: false
      t.string :currency, null: false, default: "points"
      t.integer :amount, null: false
      t.string :reason, null: false
      t.string :source_type
      t.bigint :source_id
      t.integer :balance_after, null: false
      t.string :dedupe_token
      t.timestamps
    end

    add_index :forum_point_transactions, [ :user_id, :created_at ],
              name: "idx_forum_point_tx_user_created"
    add_index :forum_point_transactions, [ :source_type, :source_id ],
              name: "idx_forum_point_tx_source"
    add_index :forum_point_transactions, :forum_point_account_id,
              name: "idx_forum_point_tx_account"

    # Source-based idempotency: only enforced when there IS a source. This lets
    # post_created / solution_accepted award once per (beneficiary, reason, source),
    # while admin_adjust (source nil) is never blocked.
    add_index :forum_point_transactions, [ :user_id, :currency, :reason, :source_type, :source_id ],
              unique: true, where: "source_id IS NOT NULL",
              name: "idx_forum_point_tx_idempotency"

    # Token-based idempotency for reactions: dedupe_token = "reaction:<post_id>:<reactor_id>"
    # ensures each distinct reactor awards the post author at most once per post lifetime,
    # surviving like/unlike/like-again (since the token does not depend on the Reaction row).
    add_index :forum_point_transactions, :dedupe_token,
              unique: true, where: "dedupe_token IS NOT NULL",
              name: "idx_forum_point_tx_dedupe_token"

    add_foreign_key :forum_point_transactions, :forum_point_accounts
    add_foreign_key :forum_point_transactions, :users
  end
end
