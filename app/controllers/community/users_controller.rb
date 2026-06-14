# frozen_string_literal: true

module Community
  class UsersController < ApplicationController
    before_action :require_login, only: %i[update]

    def show
      user = User.find_by!(username: params[:id])
      tab = params[:tab].to_s.in?(%w[topics posts]) ? params[:tab] : "topics"
      topics_scope = Community::Topic.where(user: user, status: :published).order(created_at: :desc)
      posts_scope = Community::Post.where(user: user, status: :published).includes(:topic).order(created_at: :desc)
      posts_count = posts_scope.count
      @pagy_topics, topics = pagy(topics_scope, limit: 20, page: [ params[:topics_page].to_i, 1 ].max)
      @pagy_posts, posts = pagy(posts_scope, limit: 20, page: [ params[:posts_page].to_i, 1 ].max)
      trust = Community::TrustLevel.level_info(user)
      progress = Community::TrustLevel.progress_for(user)
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
          last_seen_at: user.last_seen_at ? l(user.last_seen_at, format: :short) : nil,
          online: user.last_seen_at && user.last_seen_at > 5.minutes.ago,
          forum_signature: user.forum_signature,
          topics_count: topics_scope.count,
          posts_count: posts_count,
          followers_count: Community::UserFollow.where(followed: user).count,
          followers_url: forum_user_followers_path(user.username),
          profile_url: forum_user_path(user.username),
          message_url: logged_in? && current_user.id != user.id ? new_forum_conversation_path(to: user.username) : nil,
          block_url: logged_in? && current_user.id != user.id ? forum_block_user_path(user.username) : nil,
          ignore_url: logged_in? && current_user.id != user.id ? forum_ignore_user_path(user.username) : nil,
          is_blocked: logged_in? && current_user.id != user.id && Community::UserBlock.exists?(blocker: current_user, blocked: user),
          is_ignored: logged_in? && current_user.id != user.id && Community::UserIgnore.exists?(ignorer: current_user, ignored: user),
          is_muted: logged_in? && current_user.id == user.id && Community::Mute.muted?(user),
          mute_info: mute_info_for(user),
          can_edit: logged_in? && current_user.id == user.id,
          is_following: logged_in? && current_user.id != user.id && Community::UserFollow.exists?(follower: current_user, followed: user),
          follow_url: logged_in? && current_user.id != user.id ? forum_user_follow_path(user.username) : nil,
          trust_progress: progress
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
        topicsPagination: pagy_props(@pagy_topics),
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
        postsPagination: pagy_props(@pagy_posts),
        activeTab: tab,
        liked_posts: liked_posts
      }
    end

    def update
      user = User.find_by!(username: params[:id])
      return head :forbidden unless current_user.id == user.id

      if user.update(user_params)
        attach_forum_avatar!(user) if params[:user][:forum_avatar].present?
        remove_forum_avatar!(user) if ActiveModel::Type::Boolean.new.cast(params.dig(:user, :remove_forum_avatar))
        redirect_to forum_user_path(user.username), notice: "资料已更新。"
      else
        redirect_to forum_user_path(user.username), alert: user.errors.full_messages.to_sentence
      end
    end

    private

    def user_params
      params.require(:user).permit(:bio, :forum_title, :forum_signature)
    end

    def attach_forum_avatar!(user)
      file = params[:user][:forum_avatar]
      return unless file.respond_to?(:content_type)

      allowed = %w[image/jpeg image/png image/gif image/webp]
      return unless allowed.include?(file.content_type)
      return if file.size > 2.megabytes

      user.forum_avatar.attach(file)
    end

    def remove_forum_avatar!(user)
      user.forum_avatar.purge if user.forum_avatar.attached?
    end

    def mute_info_for(user)
      return nil unless logged_in? && current_user.id == user.id
      return nil unless Community::Mute.muted?(user)

      mute = Community::Mute.active.where(user: user).includes(:section).order(created_at: :desc).first
      return nil unless mute

      {
        section: mute.section&.name || "全站",
        reason: mute.reason,
        expires_at: mute.expires_at ? l(mute.expires_at, format: :short) : "永久"
      }
    end
  end
end
