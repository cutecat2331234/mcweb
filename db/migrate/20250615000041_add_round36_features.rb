# frozen_string_literal: true

class AddRound36Features < ActiveRecord::Migration[8.0]
  def change
    create_table :forum_user_warnings do |t|
      t.references :user, null: false, foreign_key: true
      t.references :issuer, null: false, foreign_key: { to_table: :users }
      t.text :reason, null: false
      t.integer :points, null: false, default: 1
      t.boolean :acknowledged, null: false, default: false
      t.timestamps
    end

    create_table :store_gift_cards do |t|
      t.string :code, null: false
      t.integer :balance_cents, null: false, default: 0
      t.integer :initial_balance_cents, null: false, default: 0
      t.string :currency, null: false, default: "CNY"
      t.boolean :active, null: false, default: true
      t.datetime :expires_at
      t.string :note
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :store_gift_cards, :code, unique: true

    add_reference :store_orders, :store_gift_card, foreign_key: true
    add_column :store_orders, :gift_card_amount_cents, :integer, null: false, default: 0
  end
end
