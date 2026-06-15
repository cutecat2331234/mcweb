# frozen_string_literal: true

class AddRound54Features < ActiveRecord::Migration[8.1]
  def change
    create_table :store_order_webhook_deliveries do |t|
      t.string :event_type, null: false
      t.string :order_public_id
      t.string :url, null: false, limit: 2048
      t.integer :response_code
      t.text :response_body
      t.string :status, null: false, default: "pending"
      t.timestamps
    end

    add_index :store_order_webhook_deliveries, :order_public_id
    add_index :store_order_webhook_deliveries, :created_at

    add_column :store_orders, :review_request_sent_at, :datetime
  end
end
