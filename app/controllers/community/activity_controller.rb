# frozen_string_literal: true

module Community
  class ActivityController < ApplicationController
    include Community::TopicListSortable

    def index
      tab = params[:tab].presence_in(%w[posts topics]) || "posts"

      if tab == "topics"
        sort = params[:sort].presence || "latest"
        scope = Community::Topic.where(status: :published).includes(:user, :section).joins(:section)
        scope = filter_blocked_topics(scope) if logged_in?
        scope = apply_forum_topic_sort(scope, sort)
        @pagy, topics = pagy(scope, limit: 30)

        read_states = if logged_in?
                          Community::ReadState.where(user: current_user, forum_topic_id: topics.map(&:id)).index_by(&:forum_topic_id)
                        else
                          {}
                        end

        render inertia: "Community/Activity/Index", props: activity_props(
          tab: tab,
          topics: topics.map { |topic| serialize_topic(topic, read_state: read_states[topic.id]) },
          sort: sort,
          sortOptions: activity_sort_options
        )
      else
        scope = Community::Post.where(status: :published)
          .includes(:user, topic: :section)
          .order(created_at: :desc)

        if logged_in?
          blocked_ids = blocked_user_ids
          scope = scope.where.not(user_id: blocked_ids) if blocked_ids.any?
        end

        @pagy, posts = pagy(scope, limit: 30)

        render inertia: "Community/Activity/Index", props: activity_props(
          tab: tab,
          posts: posts.map { |post| serialize_activity_post(post) }
        )
      end
    end

    private

    def activity_props(tab:, posts: nil, topics: nil, sort: nil, sortOptions: nil)
      {
        tab: tab,
        posts: posts || [],
        topics: topics || [],
        pagination: pagy_props(@pagy),
        sort: sort.to_s,
        sortOptions: sortOptions || []
      }
    end

    def activity_sort_options
      [
        { value: "latest", label: "最新回复" },
        { value: "hot", label: "热门" },
        { value: "replies", label: "回复最多" },
        { value: "newest", label: "最新发布" }
      ]
    end
  end
end
