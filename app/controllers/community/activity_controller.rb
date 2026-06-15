# frozen_string_literal: true

module Community
  class ActivityController < ApplicationController
    include Community::TopicListSortable
    include Community::TopicListPreloadable

    def index
      tab = params[:tab].presence_in(%w[posts topics following]) || "posts"

      case tab
      when "topics"
        render_topics_tab(tab)
      when "following"
        render_following_tab(tab)
      else
        render_posts_tab(tab)
      end
    end

    private

    def render_posts_tab(tab)
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

    def render_following_tab(tab)
      unless logged_in?
        return redirect_to forum_activity_path, alert: "请先登录查看关注动态。"
      end

      followed_ids = Community::UserFollow.where(follower: current_user).pluck(:followed_id) - blocked_user_ids
      scope = Community::Post.where(status: :published, user_id: followed_ids)
        .includes(:user, topic: :section)
        .order(created_at: :desc)
      scope = scope.joins(:topic).where(forum_topics: { status: :published, unlisted: false })
      scope = scope.where.not(forum_topics: { user_id: blocked_user_ids }) if blocked_user_ids.any?

      @pagy, posts = pagy(scope, limit: 30)

      render inertia: "Community/Activity/Index", props: activity_props(
        tab: tab,
        posts: posts.map { |post| serialize_activity_post(post) }
      )
    end

    def render_topics_tab(tab)
      sort = params[:sort].presence || "latest"
      scope = preload_topics(Community::Topic.published_listed.joins(:section))
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
        topics: serialize_topics(topics, read_states: read_states),
        sort: sort,
        sortOptions: activity_sort_options
      )
    end

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
