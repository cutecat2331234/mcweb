# frozen_string_literal: true

class AddRound45Features < ActiveRecord::Migration[8.0]
  def change
    add_column :store_products, :maximum_quantity, :integer
    add_column :store_products, :requires_shipping, :boolean, default: false, null: false
    add_column :store_coupons, :free_shipping, :boolean, default: false, null: false
  end
end
