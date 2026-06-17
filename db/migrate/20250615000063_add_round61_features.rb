# frozen_string_literal: true

class AddRound61Features < ActiveRecord::Migration[8.0]
  def change
    add_column :store_orders, :coupon_usage_restored, :boolean, default: false, null: false
  end
end
