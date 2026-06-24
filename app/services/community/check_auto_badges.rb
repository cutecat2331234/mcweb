# frozen_string_literal: true

module Community
  class CheckAutoBadges < ApplicationService
    def initialize(user:)
      @user = user
    end

    def call
      Community::Badge.where.not(grant_rule: "manual").find_each do |badge|
        next if Community::UserBadge.exists?(user: @user, badge: badge)
        next unless eligible?(badge)

        Community::AwardBadge.call(user: @user, badge_slug: badge.slug)
      end

      ServiceResult.success
    end

    private

    def eligible?(badge)
      case badge.grant_rule
      when "first_topic"
        Community::Topic.where(user: @user, status: :published).exists?
      when "posts_count"
        Community::Post.where(user: @user, status: :published).count >= badge.grant_threshold
      when "likes_received"
        Community::Reaction.joins(:post).where(forum_posts: { user_id: @user.id }).count >= badge.grant_threshold
      when "first_purchase"
        Commerce::Order.where(user: @user, status: %w[paid processing fulfilling fulfilled completed]).exists?
      when "trust_level"
        Community::TrustLevel.level_for(@user) >= badge.grant_threshold
      when "member_days"
        @user.created_at <= badge.grant_threshold.days.ago
      when "solutions"
        Community::Post.where(user: @user)
          .where(id: Community::Topic.where.not(solved_post_id: nil).select(:solved_post_id))
          .count >= badge.grant_threshold
      else
        false
      end
    end
  end
end
