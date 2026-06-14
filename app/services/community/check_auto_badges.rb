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
      else
        false
      end
    end
  end
end
