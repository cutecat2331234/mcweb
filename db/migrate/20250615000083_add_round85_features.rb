# frozen_string_literal: true

class AddRound85Features < ActiveRecord::Migration[8.1]
  def change
    create_table :forum_search_histories do |t|
      t.references :user, null: false, foreign_key: true
      t.string :query, null: false, default: ""
      t.jsonb :filters, null: false, default: {}
      t.timestamps
    end

    add_index :forum_search_histories, %i[user_id created_at]
  end
end
