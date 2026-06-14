# frozen_string_literal: true

class AddRound21Features < ActiveRecord::Migration[8.1]
  def change
    change_table :store_coupons, bulk: true do |t|
      t.integer :per_user_limit
      t.boolean :first_order_only, default: false, null: false
      t.integer :max_discount_cents
    end

    change_table :forum_topics, bulk: true do |t|
      t.datetime :pinned_until
      t.datetime :bumped_at
    end
    add_index :forum_topics, :pinned_until

    create_table :store_product_views do |t|
      t.references :user, null: false, foreign_key: true
      t.references :store_product, null: false, foreign_key: true
      t.datetime :viewed_at, null: false
      t.timestamps
    end
    add_index :store_product_views, %i[user_id store_product_id], unique: true
    add_index :store_product_views, %i[user_id viewed_at]
  end
end
