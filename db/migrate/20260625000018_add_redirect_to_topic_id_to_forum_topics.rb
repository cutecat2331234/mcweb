# frozen_string_literal: true

class AddRedirectToTopicIdToForumTopics < ActiveRecord::Migration[8.1]
  def change
    add_column :forum_topics, :redirect_to_topic_id, :bigint
    add_index :forum_topics, :redirect_to_topic_id
  end
end
