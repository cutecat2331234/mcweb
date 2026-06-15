# frozen_string_literal: true

class AddRound51Features < ActiveRecord::Migration[8.1]
  def change
    add_column :forum_topics, :archived_at, :datetime
    add_index :forum_topics, :archived_at

    add_column :store_carts, :abandoned_second_reminder_sent_at, :datetime

    add_column :users, :forum_digest_watched_only, :boolean, default: false, null: false
  end
end
