# frozen_string_literal: true

class AddForumRound8Features < ActiveRecord::Migration[8.1]
  def change
    add_reference :forum_bookmarks, :forum_post, foreign_key: { to_table: :forum_posts }, index: true
    add_index :forum_bookmarks, [ :user_id, :forum_post_id ], unique: true, where: "forum_post_id IS NOT NULL"

    add_column :store_products, :gallery_urls, :jsonb, default: [], null: false
  end
end
