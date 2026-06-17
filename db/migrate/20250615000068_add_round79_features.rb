# frozen_string_literal: true

class AddRound79Features < ActiveRecord::Migration[8.1]
  def change
    create_table :forum_saved_search_webhook_deliveries do |t|
      t.references :saved_search, null: false, foreign_key: { to_table: :forum_saved_searches }
      t.string :event_type, null: false
      t.string :url, null: false, limit: 2048
      t.integer :response_code
      t.text :response_body
      t.string :status, null: false, default: "pending"
      t.timestamps
    end

    add_index :forum_saved_search_webhook_deliveries, :created_at
  end
end
