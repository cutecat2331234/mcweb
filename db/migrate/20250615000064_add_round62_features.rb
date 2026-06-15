# frozen_string_literal: true

class AddRound62Features < ActiveRecord::Migration[8.0]
  def change
    add_column :store_orders, :gift_card_restored_cents, :integer, default: 0, null: false
  end
end
