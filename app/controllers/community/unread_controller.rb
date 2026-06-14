# frozen_string_literal: true

module Community
  class UnreadController < ApplicationController
    before_action :require_login

    def index
      read_states = Community::ReadState
        .where(user: current_user)
        .where("unread_count > 0")

      topic_ids = read_states.pluck(:forum_topic_id)
      topics = Community::Topic
        .where(id: topic_ids, status: :published)
        .includes(:user, :section)
        .order(last_posted_at: :desc)
        .limit(50)

      states_by_topic = read_states.index_by(&:forum_topic_id)

      render inertia: "Community/Unread/Index", props: {
        topics: topics.map { |topic| serialize_topic(topic, read_state: states_by_topic[topic.id]) }
      }
    end
  end
end
