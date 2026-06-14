# frozen_string_literal: true

class AddRound44Features < ActiveRecord::Migration[8.0]
  def change
    add_column :forum_sections, :link_url, :string
    add_column :forum_sections, :link_label, :string
    add_column :store_products, :minimum_quantity, :integer, default: 1, null: false
  end
end
