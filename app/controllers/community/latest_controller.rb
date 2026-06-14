# frozen_string_literal: true

module Community
  class LatestController < ApplicationController
    include Community::TopicFilterable
    include Community::TopicListPreloadable

    def index
      sort = params[:sort].to_s.presence || "activity"
      filter = params[:filter].to_s.presence
      scope = preload_topics(Community::Topic.where(status: :published).sorted(sort))
      scope = filter_blocked_topics(scope)
      scope = apply_topic_filter(scope, filter: filter, user: current_user)

      @pagy, topics = pagy(scope, limit: 30)

      read_states = if logged_in?
                      Community::ReadState.where(user: current_user, forum_topic_id: topics.map(&:id)).index_by(&:forum_topic_id)
                    else
                      {}
                    end

      render inertia: "Community/Latest/Index", props: {
        topics: serialize_topics(topics, read_states: read_states),
        pagination: pagy_props(@pagy),
        sort: sort,
        filter: filter.to_s,
        filterOptions: topic_filter_options,
        rss_url: forum_latest_rss_path
      }
    end
  end
end
