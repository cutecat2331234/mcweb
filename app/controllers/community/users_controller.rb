# frozen_string_literal: true

module Community
  class UsersController < ApplicationController
    before_action :require_login, only: %i[update]

    def show
      user = User.find_by!(username: params[:id])
      topics_scope = Community::Topic.where(user: user, status: :published)
      topics = topics_scope.order(created_at: :desc).limit(20)
      posts = Community::Post.where(user: user, status: :published)
        .includes(:topic)
        .order(created_at: :desc)
        .limit(20)
      posts_count = Community::Post.where(user: user, status: :published).count
      trust = Community::TrustLevel.level_info(user)
      liked_posts = Community::Post.where(user: user, status: :published)
        .select("forum_posts.*, COUNT(forum_reactions.id) AS reactions_count")
        .joins(:reactions)
        .group("forum_posts.id")
        .order(Arel.sql("COUNT(forum_reactions.id) DESC"))
        .limit(10)
        .includes(:topic)
        .map do |post|
          {
            id: post.id,
            body: post.body.truncate(100),
            floor_number: post.floor_number,
            topic_title: post.topic.title,
            topic_url: forum_topic_path(post.topic),
            likes_count: post[:reactions_count].to_i
          }
        end

      render inertia: "Community/Users/Show", props: {
        profile: {
          username: user.username,
          display_name: user.display_name,
          forum_title: user.forum_title,
          avatar_url: user.avatar_url,
          bio: user.bio,
          trust_level: trust[:level],
          trust_name: trust[:name],
          likes_received: Community::Reaction.joins(:post).where(forum_posts: { user_id: user.id }).count,
          member_since: l(user.created_at, format: :long),
          topics_count: topics_scope.count,
          posts_count: posts_count,
          profile_url: forum_user_path(user.username),
          message_url: logged_in? && current_user.id != user.id ? new_forum_conversation_path(to: user.username) : nil,
          block_url: logged_in? && current_user.id != user.id ? forum_block_user_path(user.username) : nil,
          is_blocked: logged_in? && current_user.id != user.id && Community::UserBlock.exists?(blocker: current_user, blocked: user),
          is_muted: logged_in? && current_user.id == user.id && Community::Mute.muted?(user),
          can_edit: logged_in? && current_user.id == user.id,
          is_following: logged_in? && current_user.id != user.id && Community::UserFollow.exists?(follower: current_user, followed: user),
          follow_url: logged_in? && current_user.id != user.id ? forum_user_follow_path(user.username) : nil
        },
        badges: user.user_badges.includes(:badge).order(granted_at: :desc).map do |ub|
          {
            name: ub.badge.name,
            icon: ub.badge.icon,
            description: ub.badge.description,
            color: ub.badge.color
          }
        end,
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
        end,
        liked_posts: liked_posts
      }
    end

    def update
      user = User.find_by!(username: params[:id])
      return head :forbidden unless current_user.id == user.id

      if user.update(user_params)
        redirect_to forum_user_path(user.username), notice: "资料已更新。"
      else
        redirect_to forum_user_path(user.username), alert: user.errors.full_messages.to_sentence
      end
    end

    private

    def user_params
      params.require(:user).permit(:bio, :forum_title)
    end
  end
end
