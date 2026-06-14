# frozen_string_literal: true

class AddRound13Features < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :forum_digest_frequency, :string, default: "none", null: false
    add_column :users, :forum_digest_last_sent_at, :datetime

    create_table :forum_user_follows do |t|
      t.references :follower, null: false, foreign_key: { to_table: :users }
      t.references :followed, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :forum_user_follows, %i[follower_id followed_id], unique: true

    create_table :store_stock_alerts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :store_product, null: false, foreign_key: true
      t.references :store_product_variant, foreign_key: true
      t.datetime :notified_at
      t.timestamps
    end
    add_index :store_stock_alerts, %i[user_id store_product_id store_product_variant_id],
              unique: true, name: "index_stock_alerts_on_user_product_variant"
  end
end
