# frozen_string_literal: true

class AddRound80Features < ActiveRecord::Migration[8.1]
  def change
    change_table :forum_saved_search_webhook_deliveries, bulk: true do |t|
      t.jsonb :request_payload, default: {}, null: false
    end
  end
end
