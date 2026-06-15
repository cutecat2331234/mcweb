# frozen_string_literal: true

module Community
  class AssignedController < ApplicationController
    include Community::TopicListSortable
    include Community::TopicListPreloadable

    before_action :require_login

    def index
      sort = params[:sort].presence || "latest"
      scope = preload_topics(
        Community::Topic.published_listed
          .where(assigned_to: current_user)
          .includes(:assigned_to)
      )
      scope = filter_blocked_topics(scope)
      scope = apply_forum_topic_sort(scope, sort)

      @pagy, topics = pagy(scope, limit: 20)
      read_states = Community::ReadState
        .where(user: current_user, forum_topic_id: topics.map(&:id))
        .index_by(&:forum_topic_id)

      render inertia: "Community/Assigned/Index", props: {
        topics: serialize_topics(topics, read_states: read_states),
        pagination: pagy_props(@pagy),
        sort: sort,
        sortOptions: forum_sort_options,
        canBulkModerate: current_user.permission?("forum.topics.lock"),
        bulkModerateUrl: current_user.permission?("forum.topics.lock") ? bulk_moderate_forum_topics_path : nil
      }
    end

    private

    def forum_sort_options
      [
        { value: "latest", label: "最新回复" },
        { value: "hot", label: "热门" },
        { value: "replies", label: "回复最多" },
        { value: "newest", label: "最新发布" }
      ]
    end
  end
end
