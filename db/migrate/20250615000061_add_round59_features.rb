# frozen_string_literal: true

class AddRound59Features < ActiveRecord::Migration[8.0]
  def change
    add_column :store_orders, :store_credit_restored_cents, :integer, default: 0, null: false
    add_column :forum_tag_groups, :color_hex, :string

    create_table :store_product_availability_alerts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :store_product, null: false, foreign_key: true
      t.datetime :notified_at
      t.timestamps
    end

    add_index :store_product_availability_alerts, %i[user_id store_product_id],
              unique: true, name: "index_availability_alerts_on_user_and_product"
  end
end
