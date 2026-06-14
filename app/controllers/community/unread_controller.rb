# frozen_string_literal: true

module Community
  class UnreadController < ApplicationController
    before_action :require_login

    def index
      read_states = Community::ReadState
        .where(user: current_user)
        .includes(topic: :posts)
        .select { |state| state.unread_count.positive? }
        .sort_by { |state| state.topic.last_posted_at || Time.at(0) }
        .reverse
        .first(50)

      topics = read_states.map(&:topic).select { |topic| topic.status == "published" }
      topics = topics.reject { |topic| blocked_user_ids.include?(topic.user_id) }
      states_by_topic = read_states.index_by(&:forum_topic_id)

      render inertia: "Community/Unread/Index", props: {
        topics: topics.map { |topic| serialize_topic(topic, read_state: states_by_topic[topic.id]) }
      }
    end
  end
end
