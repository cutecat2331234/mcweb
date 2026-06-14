# frozen_string_literal: true

class AddRound41Features < ActiveRecord::Migration[8.0]
  def change
    add_column :forum_tags, :color_hex, :string
    add_column :forum_topics, :unlisted, :boolean, default: false, null: false
    add_column :forum_posts, :staff_notice, :text

    add_column :store_categories, :icon, :string
    add_column :store_categories, :color_hex, :string
    add_column :store_coupons, :description, :text
  end
end
