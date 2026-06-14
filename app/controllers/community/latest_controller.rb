# frozen_string_literal: true

module Community
  class LatestController < ApplicationController
    def index
      sort = params[:sort].to_s.presence || "activity"
      scope = Community::Topic.where(status: :published).sorted(sort).includes(:user, :section)
      scope = filter_blocked_topics(scope)

      @pagy, topics = pagy(scope, limit: 30)

      read_states = if logged_in?
                      Community::ReadState.where(user: current_user, forum_topic_id: topics.map(&:id)).index_by(&:forum_topic_id)
                    else
                      {}
                    end

      render inertia: "Community/Latest/Index", props: {
        topics: topics.map { |topic| serialize_topic(topic, read_state: read_states[topic.id]) },
        pagination: pagy_props(@pagy),
        sort: sort,
        rss_url: forum_latest_rss_path
      }
    end
  end
end
