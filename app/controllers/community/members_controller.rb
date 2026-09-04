# frozen_string_literal: true

module Community
  class MembersController < ApplicationController
    include ViewerScopedNoStoreResponse

    def index
      scope = User.where(status: :active)
      private_directory_visible = Community::UserProfileVisibility.private_directory_visible?(viewer: current_user)
      if params[:q].present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
        scope = scope.where("username ILIKE ? OR display_name ILIKE ?", q, q)
      end

      sort = normalized_member_sort(params[:sort], private_directory_visible: private_directory_visible)
      trust_level = params[:trust_level].to_s.presence
      group_id = params[:group].to_s.presence
      scope = apply_member_sort(scope, sort)
      scope = apply_trust_level_filter(scope, trust_level) if trust_level.present?
      if group_id.present?
        scope = scope.where(id: Community::GroupMembership.where(community_user_group_id: group_id).select(:user_id))
      end

      @pagy, members = pagy(:offset, scope, limit: 30)
      stats = member_stats(members)

      render inertia: "Community/Members/Index", props: {
        members: members.map { |user| serialize_member(user, stats: stats) },
        pagination: pagy_props(@pagy),
        query: params[:q].to_s,
        sort: sort,
        trustLevel: trust_level.to_s,
        group: group_id.to_s,
        groupOptions: Community::UserGroup.ordered.map { |g| { value: g.id.to_s, label: g.name } },
        availableSorts: available_member_sorts(private_directory_visible: private_directory_visible),
        onlineCount: private_directory_visible ? User.where(status: :active).where("last_seen_at > ?", 5.minutes.ago).count : nil
      }, encrypt_history: true
    end

    private

    def normalized_member_sort(value, private_directory_visible:)
      allowed = available_member_sorts(private_directory_visible: private_directory_visible)
      default = private_directory_visible ? "active" : "posts"
      requested = value.to_s.presence
      requested && allowed.include?(requested) ? requested : default
    end

    def available_member_sorts(private_directory_visible:)
      sorts = Community::UserProfileVisibility::PUBLIC_MEMBER_SORTS
      return sorts unless private_directory_visible

      Community::UserProfileVisibility::PRIVATE_MEMBER_SORTS + sorts
    end

    def apply_member_sort(scope, sort)
      case sort
      when "joined"
        scope.order(created_at: :desc, id: :desc)
      when "posts"
        scope.order(Arel::Nodes::Descending.new(member_post_count_subquery), created_at: :desc, id: :desc)
      when "likes"
        scope.order(Arel::Nodes::Descending.new(member_reaction_count_subquery), created_at: :desc, id: :desc)
      when "reviews"
        scope.order(
          Arel.sql("(SELECT COUNT(*) FROM store_reviews WHERE store_reviews.user_id = users.id AND store_reviews.status = 'published') DESC"),
          created_at: :desc,
          id: :desc
        )
      when "purchases"
        scope.order(
          Arel::Nodes::Descending.new(member_purchase_count_subquery),
          created_at: :desc,
          id: :desc
        )
      when "online"
        scope.where("last_seen_at > ?", 5.minutes.ago).order(last_seen_at: :desc, id: :desc)
      when "active"
        scope.order(Arel.sql("last_seen_at DESC NULLS LAST"), created_at: :desc, id: :desc)
      else
        scope.order(Arel::Nodes::Descending.new(member_post_count_subquery), created_at: :desc, id: :desc)
      end
    end

    def apply_trust_level_filter(scope, trust_level)
      level = trust_level.to_i
      return scope unless level.between?(0, 4)

      thresholds = Community::TrustLevel::LEVELS
      min_posts = thresholds.find { |entry| entry[:level] == level }&.dig(:min_posts) || 0
      next_entry = thresholds.find { |entry| entry[:level] == level + 1 }
      max_posts = next_entry&.dig(:min_posts)
      posts_sql = "(SELECT COUNT(*) FROM forum_posts WHERE forum_posts.user_id = users.id AND forum_posts.status = 'published')"

      auto_scope = scope.where(forum_trust_level_override: nil).where("#{posts_sql} >= ?", min_posts)
      auto_scope = auto_scope.where("#{posts_sql} < ?", max_posts) if max_posts

      scope.where(forum_trust_level_override: level).or(auto_scope)
    end

    def member_stats(members)
      ids = members.map(&:id)
      posts = listed_posts.where(user_id: ids)
      purchase_ids = members.filter_map do |user|
        user.id if user_profile_activity(user).visible?
      end
      {
        posts: posts.group(:user_id).count,
        likes: Community::Reaction.joins(:post)
          .where(forum_post_id: posts.select(:id))
          .group("forum_posts.user_id").count,
        reviews: Commerce::Review.where(user_id: ids, status: :published).group(:user_id).count,
        purchases: Commerce::Order
          .where(
            user_id: purchase_ids,
            status: Community::UserProfileActivitySerializer::COMPLETED_ORDER_STATUSES
          )
          .group(:user_id).count
      }
    end

    def listed_posts
      @listed_posts ||= Community::ForumAccess.listed_post_scope(
        relation: Community::Post.all,
        user: current_user
      )
    end

    def member_post_count_subquery
      posts = Community::Post.arel_table
      users = User.arel_table
      count_subquery(listed_posts.where(posts[:user_id].eq(users[:id])))
    end

    def member_reaction_count_subquery
      posts = Community::Post.arel_table
      users = User.arel_table
      post_ids = listed_posts.where(posts[:user_id].eq(users[:id])).select(:id)
      count_subquery(Community::Reaction.where(forum_post_id: post_ids))
    end

    def member_purchase_count_subquery
      orders = Commerce::Order.arel_table
      users = User.arel_table
      count_subquery(
        Commerce::Order
          .where(orders[:user_id].eq(users[:id]))
          .where(status: Community::UserProfileActivitySerializer::COMPLETED_ORDER_STATUSES)
      )
    end

    def count_subquery(relation)
      count = Arel::Nodes::Count.new([ Arel.star ])
      Arel::Nodes::Grouping.new(relation.reorder(nil).select(count).arel.ast)
    end

    def serialize_member(user, stats:)
      level = Community::TrustLevel.level_for(user)
      trust = Community::TrustLevel::LEVELS.find { |entry| entry[:level] == level } || Community::TrustLevel::LEVELS.first
      payload = {
        username: user.username,
        display_name: user.display_name,
        avatar_url: user.avatar_url,
        profile_url: forum_user_path(user.username),
        posts_count: stats[:posts][user.id].to_i,
        likes_received: stats[:likes][user.id].to_i,
        reviews_count: stats[:reviews][user.id].to_i,
        trust_level: trust[:level],
        trust_name: trust[:name],
        member_since: l(user.created_at, format: :short)
      }

      payload.merge!(
        user_profile_activity(user).member(purchases_count: stats[:purchases][user.id])
      )
    end

    def user_profile_activity(user)
      @user_profile_activity ||= {}
      serializer = @user_profile_activity[user.id] ||= Community::UserProfileActivitySerializer.new(
        user: user,
        viewer: current_user
      )
      mark_viewer_scoped_no_store_response! if serializer.visible?
      serializer
    end
  end
end
