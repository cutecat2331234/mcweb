# frozen_string_literal: true

module Community
  class MembersController < ApplicationController
    def index
      scope = User.where(status: :active)
      if params[:q].present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
        scope = scope.where("username ILIKE ? OR display_name ILIKE ?", q, q)
      end

      sort = params[:sort].to_s.presence || "active"
      trust_level = params[:trust_level].to_s.presence
      scope = apply_member_sort(scope, sort)
      scope = apply_trust_level_filter(scope, trust_level) if trust_level.present?

      @pagy, members = pagy(scope, limit: 30)
      stats = member_stats(members)

      render inertia: "Community/Members/Index", props: {
        members: members.map { |user| serialize_member(user, stats: stats) },
        pagination: pagy_props(@pagy),
        query: params[:q].to_s,
        sort: sort,
        trustLevel: trust_level.to_s
      }
    end

    private

    def apply_member_sort(scope, sort)
      case sort
      when "joined"
        scope.order(created_at: :desc)
      when "posts"
        scope.order(Arel.sql("(SELECT COUNT(*) FROM forum_posts WHERE forum_posts.user_id = users.id AND forum_posts.status = 'published') DESC"))
      when "likes"
        scope.order(Arel.sql(<<~SQL.squish))
          (SELECT COUNT(*) FROM forum_reactions
           INNER JOIN forum_posts ON forum_posts.id = forum_reactions.forum_post_id
           WHERE forum_posts.user_id = users.id) DESC
        SQL
      when "reviews"
        scope.order(Arel.sql("(SELECT COUNT(*) FROM store_reviews WHERE store_reviews.user_id = users.id AND store_reviews.status = 'published') DESC"))
      when "purchases"
        scope.order(Arel.sql(<<~SQL.squish))
          (SELECT COUNT(*) FROM store_orders
           WHERE store_orders.user_id = users.id
           AND store_orders.status IN ('paid','processing','fulfilling','fulfilled','completed')) DESC
        SQL
      when "online"
        scope.where("last_seen_at > ?", 5.minutes.ago).order(last_seen_at: :desc)
      else
        scope.order(Arel.sql("last_seen_at DESC NULLS LAST, created_at DESC"))
      end
    end

    def apply_trust_level_filter(scope, trust_level)
      level = trust_level.to_i
      thresholds = Community::TrustLevel::LEVELS.map { |entry| entry[:min_posts] }
      min_posts = thresholds[level] || 0
      max_posts = thresholds[level + 1]

      posts_sql = "(SELECT COUNT(*) FROM forum_posts WHERE forum_posts.user_id = users.id AND forum_posts.status = 'published')"
      scope = scope.where("#{posts_sql} >= ?", min_posts)
      scope = scope.where("#{posts_sql} < ?", max_posts) if max_posts
      scope
    end

    def member_stats(members)
      ids = members.map(&:id)
      {
        posts: Community::Post.where(user_id: ids, status: :published).group(:user_id).count,
        likes: Community::Reaction.joins(:post).where(forum_posts: { user_id: ids }).group("forum_posts.user_id").count,
        reviews: Commerce::Review.where(user_id: ids, status: :published).group(:user_id).count,
        purchases: Commerce::Order.where(user_id: ids, status: %w[paid processing fulfilling fulfilled completed]).group(:user_id).count
      }
    end

    def serialize_member(user, stats:)
      trust = Community::TrustLevel.level_info(user)
      {
        username: user.username,
        display_name: user.display_name,
        avatar_url: user.avatar_url,
        profile_url: forum_user_path(user.username),
        last_seen_at: user.last_seen_at ? l(user.last_seen_at, format: :short) : nil,
        online: user.last_seen_at && user.last_seen_at > 5.minutes.ago,
        posts_count: stats[:posts][user.id].to_i,
        likes_received: stats[:likes][user.id].to_i,
        reviews_count: stats[:reviews][user.id].to_i,
        purchases_count: stats[:purchases][user.id].to_i,
        trust_level: trust[:level],
        trust_name: trust[:name],
        member_since: l(user.created_at, format: :short)
      }
    end
  end
end
