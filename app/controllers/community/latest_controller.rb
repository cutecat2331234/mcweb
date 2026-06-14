# frozen_string_literal: true

module Community
  class LatestController < ApplicationController
    def index
      @pagy, topics = pagy(
        Community::Topic.where(status: :published).pinned_first.includes(:user, :section),
        limit: 30
      )

      read_states = if logged_in?
                      Community::ReadState.where(user: current_user, forum_topic_id: topics.map(&:id)).index_by(&:forum_topic_id)
                    else
                      {}
                    end

      render inertia: "Community/Latest/Index", props: {
        topics: topics.map { |topic| serialize_topic(topic, read_state: read_states[topic.id]) },
        pagination: pagy_props(@pagy)
      }
    end
  end
end
