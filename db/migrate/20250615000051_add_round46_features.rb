# frozen_string_literal: true

class AddRound46Features < ActiveRecord::Migration[8.0]
  def change
    add_column :store_products, :seo, :jsonb, default: {}, null: false

    create_table :forum_saved_searches do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :query, null: false, default: ""
      t.jsonb :filters, null: false, default: {}
      t.timestamps
    end

    add_index :forum_saved_searches, %i[user_id created_at]
  end
end
