# frozen_string_literal: true

module Community
  class UsersController < ApplicationController
    include Community::TopicListPreloadable

    before_action :require_login, only: %i[update]

    def card
      user = User.active.find_by!(username: params[:id])
      trust = Community::TrustLevel.level_info(user)
      posts_count = Community::Post.where(user: user, status: :published).count
      badges = user.user_badges.includes(:badge).order(granted_at: :desc).limit(3).map do |ub|
        {
          name: ub.badge.name,
          icon: ub.badge.icon,
          color: ub.badge.color
        }
      end
      likes_received = Community::Reaction.joins(:post).where(forum_posts: { user_id: user.id }).count
      following = logged_in? && current_user.id != user.id && Community::UserFollow.exists?(follower: current_user, followed: user)

      render json: {
        username: user.username,
        display_name: user.display_name,
        avatar_url: user.avatar_url,
        profile_url: forum_user_path(user.username),
        trust_level: trust[:level],
        trust_name: trust[:name],
        posts_count: posts_count,
        likes_received: likes_received,
        bio: user.bio.presence,
        member_since: l(user.created_at, format: :short),
        last_seen_at: user.last_seen_at ? l(user.last_seen_at, format: :short) : nil,
        online: user.last_seen_at.present? && user.last_seen_at > 5.minutes.ago,
        badges: badges,
        message_url: (logged_in? && current_user.id != user.id && Community::TrustLevel.can_send_pm?(current_user)) ? new_forum_conversation_path(to: user.username) : nil,
        follow_url: (logged_in? && current_user.id != user.id) ? forum_user_follow_path(user.username) : nil,
        following: following
      }
    end

    def show
      user = User.find_by!(username: params[:id])
      tab = params[:tab].to_s.in?(%w[topics posts store assigned]) ? params[:tab] : "topics"
      topics_scope = if logged_in? && (current_user.id == user.id || current_user.permission?("forum.topics.lock"))
                       Community::Topic.where(user: user, status: :published)
      else
                       Community::Topic.where(user: user, status: :published, unlisted: false)
      end.order(created_at: :desc)
      posts_scope = Community::Post.where(user: user, status: :published).includes(:topic).order(created_at: :desc)
      posts_count = posts_scope.count
      @pagy_topics, topics = pagy(preload_topics(topics_scope), limit: 20, page: [ params[:topics_page].to_i, 1 ].max)
      @pagy_posts, posts = pagy(posts_scope, limit: 20, page: [ params[:posts_page].to_i, 1 ].max)
      assigned_scope = Community::Topic.published_listed.where(assigned_to: user).order(last_posted_at: :desc)
      @pagy_assigned, assigned_topics = pagy(preload_topics(assigned_scope), limit: 20, page: [ params[:assigned_page].to_i, 1 ].max)
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

      store_reviews = Commerce::Review.published.where(user: user).includes(:product).order(created_at: :desc).limit(10).map do |review|
        {
          id: review.id,
          product_name: review.product.name,
          product_url: store_product_path(review.product),
          rating: review.rating,
          body: review.body&.truncate(120),
          created_at: l(review.created_at, format: :short)
        }
      end
      orders_count = Commerce::Order.where(user: user, status: %w[paid processing fulfilling fulfilled completed]).count
      store_orders = if logged_in? && current_user.id == user.id
                       Commerce::Order.where(user: user, status: %w[paid processing fulfilling fulfilled completed])
                         .order(created_at: :desc).limit(10).map do |order|
                         {
                           order_number: order.order_number,
                           status_label: order_status_label(order.status),
                           total_label: format_money(order.total_cents, order.currency),
                           url: store_order_path(order),
                           created_at: l(order.created_at, format: :short)
                         }
                       end
      else
                       []
      end

      render inertia: "Community/Users/Show", props: {
        profile: {
          username: user.username,
          display_name: user.display_name,
          forum_title: user.forum_title,
          forum_flair_color_hex: user.forum_flair_color_hex,
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
          orders_count: orders_count,
          assigned_count: assigned_scope.count,
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
          trust_progress: progress,
          warning_points: (logged_in? && (current_user.id == user.id || current_user.permission?("forum.users.warn") || current_user.permission?("admin.access"))) ? Community::UserWarning.total_points_for(user) : nil,
          store_credit_label: (logged_in? && current_user.id == user.id && user.store_credit_cents.to_i.positive?) ? format_money(user.store_credit_cents.to_i, "CNY") : nil,
          store_wallet_url: (logged_in? && current_user.id == user.id) ? store_wallet_path : nil
        },
        warnings: (logged_in? && (current_user.id == user.id || current_user.permission?("forum.users.warn") || current_user.permission?("admin.access"))) ? user.forum_warnings.recent.limit(10).map do |warning|
          {
            reason: warning.reason,
            points: warning.points,
            issuer: warning.issuer.username,
            created_at: l(warning.created_at, format: :short)
          }
        end : [],
        badges: user.user_badges.includes(:badge).order(granted_at: :desc).map do |ub|
          {
            name: ub.badge.name,
            icon: ub.badge.icon,
            description: ub.badge.description,
            color: ub.badge.color
          }
        end,
        topics: serialize_topics(topics),
        topicsPagination: pagy_props(@pagy_topics),
        assigned_topics: serialize_topics(assigned_topics),
        assignedPagination: pagy_props(@pagy_assigned),
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
        liked_posts: liked_posts,
        store_reviews: store_reviews,
        store_orders: store_orders
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
      params.require(:user).permit(:bio, :forum_title, :forum_signature, :forum_flair_color_hex)
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
