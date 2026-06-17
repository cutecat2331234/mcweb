# frozen_string_literal: true

class AddRound55Features < ActiveRecord::Migration[8.1]
  def change
    add_reference :forum_topics, :assigned_to, foreign_key: { to_table: :users }, index: true
    add_column :users, :forum_trust_level_override, :integer
    add_column :store_cart_items, :gift_note, :string, limit: 200

    create_table :store_shipping_addresses do |t|
      t.references :user, null: false, foreign_key: true
      t.string :label, limit: 50
      t.string :name, null: false
      t.string :phone, null: false
      t.string :line1, null: false
      t.string :line2
      t.string :city, null: false
      t.string :province, null: false
      t.string :postal_code
      t.boolean :default_address, default: false, null: false
      t.timestamps
    end

    add_index :store_shipping_addresses, [ :user_id, :default_address ]
  end
end
