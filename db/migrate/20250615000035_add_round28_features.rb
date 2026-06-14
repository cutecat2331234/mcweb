# frozen_string_literal: true

class AddRound28Features < ActiveRecord::Migration[8.0]
  def change
    create_table :forum_topic_mutes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :forum_topic, null: false, foreign_key: { to_table: :forum_topics }
      t.timestamps
    end

    add_index :forum_topic_mutes, %i[user_id forum_topic_id], unique: true
  end
end
