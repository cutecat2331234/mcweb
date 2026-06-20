# frozen_string_literal: true

class AddRound112Features < ActiveRecord::Migration[8.0]
  def change
    create_table :forum_event_webhook_deliveries do |t|
      t.string :event_type, null: false
      t.references :forum_topic, foreign_key: true, null: true
      t.references :forum_post, foreign_key: true, null: true
      t.string :url, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :request_payload, default: {}
      t.integer :response_code
      t.text :response_body
      t.integer :attempt_count, null: false, default: 1
      t.timestamps
    end

    add_index :forum_event_webhook_deliveries, :created_at
    add_index :forum_event_webhook_deliveries, :event_type
    add_index :forum_event_webhook_deliveries, :status
  end
end
