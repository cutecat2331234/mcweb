# frozen_string_literal: true

class AddRound47Features < ActiveRecord::Migration[8.0]
  def change
    add_column :forum_topics, :source_post_id, :bigint
    add_index :forum_topics, :source_post_id
    add_foreign_key :forum_topics, :forum_posts, column: :source_post_id

    add_column :forum_sections, :default_notification_level, :string, default: "watching", null: false

    add_column :store_categories, :seo, :jsonb, default: {}, null: false

    add_column :store_orders, :shipping_address, :jsonb, default: {}, null: false

    add_column :store_carts, :recovery_token, :string
    add_index :store_carts, :recovery_token, unique: true
  end
end
