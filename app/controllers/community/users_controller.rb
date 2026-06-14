# frozen_string_literal: true

module Community
  class UsersController < ApplicationController
    def show
      user = User.find_by!(username: params[:id])
      topics_scope = Community::Topic.where(user: user, status: :published)
      topics = topics_scope.order(created_at: :desc).limit(20)
      posts = Community::Post.where(user: user, status: :published)
        .includes(:topic)
        .order(created_at: :desc)
        .limit(20)
      posts_count = Community::Post.where(user: user, status: :published).count

      render inertia: "Community/Users/Show", props: {
        profile: {
          username: user.username,
          avatar_url: user.avatar_url,
          member_since: l(user.created_at, format: :long),
          topics_count: topics_scope.count,
          posts_count: posts_count,
          profile_url: forum_user_path(user.username),
          message_url: logged_in? && current_user.id != user.id ? new_forum_conversation_path(to: user.username) : nil,
          is_muted: logged_in? && current_user.id == user.id && Community::Mute.muted?(user)
        },
        topics: topics.map { |topic| serialize_topic(topic) },
        recent_posts: posts.map do |post|
          {
            id: post.id,
            body: post.body.truncate(120),
            floor_number: post.floor_number,
            topic_title: post.topic.title,
            topic_url: forum_topic_path(post.topic),
            created_at: l(post.created_at, format: :short)
          }
        end
      }
    end
  end
end
