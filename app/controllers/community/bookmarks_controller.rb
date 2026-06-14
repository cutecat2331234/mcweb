# frozen_string_literal: true

module Community
  class BookmarksController < ApplicationController
    before_action :require_login

    def index
      topic_ids = Community::Bookmark.where(user: current_user).pluck(:forum_topic_id)
      topics = Community::Topic
        .where(id: topic_ids, status: :published)
        .includes(:user, :section)
        .order(last_posted_at: :desc)
        .limit(50)

      read_states = Community::ReadState
        .where(user: current_user, forum_topic_id: topics.map(&:id))
        .index_by(&:forum_topic_id)

      render inertia: "Community/Bookmarks/Index", props: {
        topics: topics.map { |topic| serialize_topic(topic, read_state: read_states[topic.id]) }
      }
    end
  end
end
