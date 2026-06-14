# frozen_string_literal: true

class AddRound16Features < ActiveRecord::Migration[8.0]
  def change
    change_table :store_products, bulk: true do |t|
      t.boolean :featured, default: false, null: false
      t.integer :view_count, default: 0, null: false
      t.string :version
      t.text :changelog
    end
  end
end
