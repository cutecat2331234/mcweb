# frozen_string_literal: true

class CreateCommunityPushSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :community_push_subscriptions do |t|
      t.bigint :user_id, null: false
      t.string :endpoint, null: false
      t.string :p256dh_key, null: false
      t.string :auth_key, null: false
      t.timestamps
    end

    add_index :community_push_subscriptions, :user_id
    add_index :community_push_subscriptions, :endpoint, unique: true
    add_foreign_key :community_push_subscriptions, :users
  end
end
