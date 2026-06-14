# frozen_string_literal: true

class AddRound42Features < ActiveRecord::Migration[8.0]
  def change
    add_column :forum_categories, :color_hex, :string
    add_column :forum_categories, :icon, :string
    add_column :forum_sections, :banner_text, :text
    add_column :store_wishlist_items, :note, :text
    add_column :store_orders, :shipping_cents, :integer, default: 0, null: false
  end
end
