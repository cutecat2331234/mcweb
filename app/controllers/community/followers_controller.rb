# frozen_string_literal: true

module Community
  class FollowersController < ApplicationController
    def index
      user = User.find_by!(username: params[:username])
      scope = Community::UserFollow.where(followed: user).includes(:follower).order(created_at: :desc)
      @pagy, follows = pagy(:offset, scope, limit: 30)

      render inertia: "Community/Followers/Index", props: {
        profile: {
          username: user.username,
          display_name: user.display_name,
          profile_url: forum_user_path(user.username),
          followers_count: Community::UserFollow.where(followed: user).count
        },
        followers: follows.map do |follow|
          follower = follow.follower
          {
            username: follower.username,
            display_name: follower.display_name,
            forum_title: follower.forum_title,
            avatar_url: follower.avatar_url,
            profile_url: forum_user_path(follower.username),
            followed_at: l(follow.created_at, format: :short)
          }
        end,
        pagination: pagy_props(@pagy)
      }
    end
  end
end
