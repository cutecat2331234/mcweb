# frozen_string_literal: true

module Community
  class FollowsController < ApplicationController
    before_action :require_login

    def index
      follows = Community::UserFollow.where(follower: current_user).includes(:followed)

      render inertia: "Community/Following/Index", props: {
        users: follows.map do |follow|
          user = follow.followed
          {
            username: user.username,
            display_name: user.display_name,
            forum_title: user.forum_title,
            avatar_url: user.avatar_url,
            profile_url: forum_user_path(user.username),
            unfollow_url: forum_user_follow_path(user.username)
          }
        end
      }
    end

    def create
      result = Community::ToggleUserFollow.call(follower: current_user, followed_username: params[:username])

      if result.success?
        notice = result.value[:following] ? "已关注用户。" : "已取消关注。"
        redirect_back fallback_location: forum_user_path(params[:username]), notice: notice
      else
        redirect_back fallback_location: forum_path, alert: service_error_message(result)
      end
    end
  end
end
