# frozen_string_literal: true

class AddRound52Features < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :dismissed_global_announcement_ids, :jsonb, default: [], null: false

    add_column :forum_topics, :auto_open_at, :datetime
    add_index :forum_topics, :auto_open_at

    add_column :store_reviews, :merchant_reply, :text
    add_column :store_reviews, :merchant_replied_at, :datetime
  end
end
