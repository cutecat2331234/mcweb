# frozen_string_literal: true

module Community
  class UsersController < ApplicationController
    def show
      user = User.find_by!(username: params[:id])
      topics_scope = Community::Topic.where(user: user, status: :published)
      topics = topics_scope.order(created_at: :desc).limit(20)
      posts_count = Community::Post.where(user: user, status: :published).count

      render inertia: "Community/Users/Show", props: {
        profile: {
          username: user.username,
          avatar_url: user.avatar_url,
          member_since: l(user.created_at, format: :long),
          topics_count: topics_scope.count,
          posts_count: posts_count,
          profile_url: forum_user_path(user.username),
          message_url: logged_in? && current_user.id != user.id ? new_forum_conversation_path(to: user.username) : nil
        },
        topics: topics.map { |topic| serialize_topic(topic) }
      }
    end
  end
end
