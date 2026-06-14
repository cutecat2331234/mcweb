# frozen_string_literal: true

class AddRound24Features < ActiveRecord::Migration[8.0]
  def change
    create_table :forum_reply_drafts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :forum_topic, null: false, foreign_key: { to_table: :forum_topics }
      t.text :body, null: false, default: ""
      t.timestamps
    end

    add_index :forum_reply_drafts, %i[user_id forum_topic_id], unique: true
  end
end
