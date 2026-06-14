# frozen_string_literal: true

class AddCompareAtPriceToStoreProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :store_products, :compare_at_price_cents, :integer
  end
end
