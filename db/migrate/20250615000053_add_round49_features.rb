# frozen_string_literal: true

class AddRound49Features < ActiveRecord::Migration[8.0]
  def change
    add_column :forum_categories, :seo, :jsonb, default: {}, null: false
    add_column :forum_sections, :seo, :jsonb, default: {}, null: false

    add_column :store_orders, :shipping_method, :string
    add_column :store_orders, :tracking_number, :string
    add_column :store_orders, :shipping_carrier, :string
    add_column :store_orders, :shipped_at, :datetime
  end
end
