# frozen_string_literal: true

class AddRound39Features < ActiveRecord::Migration[8.0]
  def change
    add_column :forum_sections, :read_only, :boolean, default: false, null: false

    create_table :forum_user_silences do |t|
      t.references :user, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.text :reason
      t.datetime :expires_at
      t.timestamps
    end
    add_index :forum_user_silences, [ :user_id, :expires_at ]

    create_table :forum_canned_responses do |t|
      t.string :title, null: false
      t.text :body, null: false
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_column :store_categories, :description, :text

    create_table :store_gift_card_transactions do |t|
      t.references :store_gift_card, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.string :transaction_type, null: false
      t.bigint :store_order_id
      t.integer :balance_after_cents, null: false
      t.datetime :created_at, null: false
      t.index :store_order_id
      t.index [ :store_gift_card_id, :created_at ]
    end
    add_foreign_key :store_gift_card_transactions, :store_orders, column: :store_order_id
  end
end
