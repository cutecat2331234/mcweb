# frozen_string_literal: true

class AddRound68Features < ActiveRecord::Migration[8.1]
  def change
    create_table :store_wishlist_filter_presets do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.jsonb :filters, null: false, default: {}
      t.timestamps
    end

    add_index :store_wishlist_filter_presets, %i[user_id created_at]
  end
end
