# frozen_string_literal: true

class CreateWebhookSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_subscriptions do |t|
      t.string :name, null: false
      t.string :url, null: false
      # A Mcweb::Events catalog event name, or "*" for all catalog events.
      t.string :event, null: false, default: "*"
      t.string :secret
      t.boolean :active, null: false, default: true
      t.datetime :last_delivered_at
      t.string :last_status
      t.integer :failure_count, null: false, default: 0
      t.datetime :disabled_at
      t.bigint :created_by_id
      t.timestamps
    end

    add_index :webhook_subscriptions, [ :active, :event ]
    add_foreign_key :webhook_subscriptions, :users, column: :created_by_id, on_delete: :nullify
  end
end
