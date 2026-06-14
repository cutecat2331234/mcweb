# frozen_string_literal: true

class AddRound18Features < ActiveRecord::Migration[8.1]
  def change
    remove_index :forum_bookmarks, name: "index_forum_bookmarks_on_user_id_and_forum_topic_id"
    add_index :forum_bookmarks, %i[user_id forum_topic_id],
              unique: true,
              where: "forum_post_id IS NULL",
              name: "index_forum_bookmarks_on_user_topic_without_post"

    add_column :forum_polls, :hide_results_until_vote, :boolean, default: false, null: false
    add_column :forum_topics, :auto_close_at, :datetime
    add_index :forum_topics, :auto_close_at
  end
end
