# frozen_string_literal: true

module Community
  class TopController < ApplicationController
    include Community::TopicFilterable
    include Community::TopicListPreloadable
    include Community::SectionVisibility

    def index
      period = Community::Topic.top_period?(params[:period]) ? params[:period].to_s : Community::Topic::DEFAULT_TOP_PERIOD
      filter = params[:filter].to_s.presence
      since = Community::Topic.top_period_start(period)

      scope = Community::Topic.published_listed.accessible_by(current_user)
      scope = preload_topics(scope)
      scope = filter_blocked_topics(scope)
      scope = apply_topic_filter(scope, filter: filter, user: current_user)
      scope = scope.top_ranked(since)

      @pagy, topics = pagy(:offset, scope, limit: 30)

      read_states = if logged_in?
                      Community::ReadState.where(user: current_user, forum_topic_id: topics.map(&:id)).index_by(&:forum_topic_id)
      else
                      {}
      end

      render inertia: "Community/Top/Index", props: {
        topics: serialize_topics(topics, read_states: read_states),
        pagination: pagy_props(@pagy),
        period: period,
        periodOptions: period_options,
        filter: filter.to_s,
        filterOptions: topic_filter_options,
        activeFilters: Community::TopicListActiveFilters.call(filter: filter),
        rss_url: forum_top_rss_path(period: period),
        canBulkModerate: logged_in? && current_user.permission?("forum.topics.lock"),
        bulkModerateUrl: logged_in? && current_user.permission?("forum.topics.lock") ? bulk_moderate_forum_topics_path : nil
      }
    end

    private

    def period_options
      Community::Topic::TOP_PERIODS.keys.map do |value|
        { value: value, label: t("mcweb.forum.top_period.#{value}") }
      end
    end
  end
end
