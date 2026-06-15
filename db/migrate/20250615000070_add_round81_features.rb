# frozen_string_literal: true

class AddRound81Features < ActiveRecord::Migration[8.1]
  def change
    change_table :forum_saved_search_webhook_deliveries, bulk: true do |t|
      t.integer :attempt_count, default: 1, null: false
    end

    change_table :store_order_webhook_deliveries, bulk: true do |t|
      t.jsonb :request_payload, default: {}, null: false
      t.integer :attempt_count, default: 1, null: false
    end
  end
end
