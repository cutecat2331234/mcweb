# frozen_string_literal: true

class AddRound60Features < ActiveRecord::Migration[8.0]
  def change
    add_column :store_order_items, :stock_restored_quantity, :integer, default: 0, null: false
  end
end
