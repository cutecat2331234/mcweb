# frozen_string_literal: true

class AddRound43Features < ActiveRecord::Migration[8.0]
  def change
    add_column :store_products, :allow_backorder, :boolean, default: false, null: false
  end
end
