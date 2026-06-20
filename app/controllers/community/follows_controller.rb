# frozen_string_literal: true

module Community
  class FollowsController < ApplicationController
    include BlockedUsersFilterable
    include Community::TopicListSortable
    include Community::TopicListPreloadable

    before_action :require_login

    def index
      tab = params[:tab].presence_in(%w[topics users]) || "topics"
      sort = params[:sort].presence || "latest"

      follows = Community::UserFollow.where(follower: current_user).includes(:followed)
      followed_ids = follows.map(&:followed_id) - blocked_user_ids

      users = follows.reject { |follow| blocked_user_ids.include?(follow.followed_id) }
      @pagy_users, paged_users = pagy_array(users, limit: 20, page_param: :users_page)

      topics_scope = preload_topics(Community::Topic.where(user_id: followed_ids, status: :published, unlisted: false))
      topics_scope = filter_blocked_topics(topics_scope)
      topics_scope = apply_forum_topic_sort(topics_scope, sort)
      @pagy_topics, topics = pagy(topics_scope, limit: 20, page_param: :topics_page)

      render inertia: "Community/Following/Index", props: {
        tab: tab,
        users: paged_users.map do |follow|
          user = follow.followed
          {
            username: user.username,
            display_name: user.display_name,
            forum_title: user.forum_title,
            avatar_url: user.avatar_url,
            profile_url: forum_user_path(user.username),
            unfollow_url: forum_user_follow_path(user.username)
          }
        end,
        usersPagination: pagy_props(@pagy_users),
        topics: serialize_topics(topics),
        topicsPagination: pagy_props(@pagy_topics),
        sort: sort,
        sortOptions: forum_sort_options
      }
    end

    def create
      result = Community::ToggleUserFollow.call(follower: current_user, followed_username: params[:username])

      if result.success?
        notice = result.value[:following] ? t("mcweb.flash.following_toggled_on") : t("mcweb.flash.following_toggled_off")
        redirect_back fallback_location: forum_user_path(params[:username]), notice: notice
      else
        redirect_back fallback_location: forum_path, alert: service_error_message(result)
      end
    end

    private

    def forum_sort_options
      Community::TopicListSortOptions.call
    end
  end
end
