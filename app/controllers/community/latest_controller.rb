# frozen_string_literal: true

module Community
  class LatestController < ApplicationController
    include Community::TopicFilterable
    include Community::TopicListPreloadable
    include Community::SectionVisibility

    def index
      sort = params[:sort].to_s.presence || "activity"
      filter = params[:filter].to_s.presence
      scope = preload_topics(Community::Topic.published_listed.accessible_by(current_user).sorted(sort))
      scope = filter_blocked_topics(scope)
      scope = apply_topic_filter(scope, filter: filter, user: current_user)

      @pagy, topics = pagy(:offset, scope, limit: 30)

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
        activeFilters: topic_list_active_filters(sort: sort, filter: filter),
        rss_url: forum_latest_rss_path,
        canBulkModerate: logged_in? && current_user.permission?("forum.topics.lock"),
        bulkModerateUrl: logged_in? && current_user.permission?("forum.topics.lock") ? bulk_moderate_forum_topics_path : nil
      }
    end

    private

    def topic_list_active_filters(sort:, filter:)
      Community::TopicListActiveFilters.call(filter: filter) +
        Community::TopicListSortActiveFilters.call(sort: sort, default: "activity")
    end
  end
end
