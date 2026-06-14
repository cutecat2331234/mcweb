# frozen_string_literal: true

module Community
  class AwardBadge < ApplicationService
    def initialize(user:, badge_slug:)
      @user = user
      @badge_slug = badge_slug.to_s
    end

    def call
      badge = Community::Badge.find_by(slug: @badge_slug)
      return ServiceResult.failure(error: "Badge not found.") unless badge

      user_badge = Community::UserBadge.find_or_initialize_by(user: @user, badge: badge)
      return ServiceResult.success(user_badge) if user_badge.persisted?

      user_badge.granted_at = Time.current
      user_badge.save!
      ServiceResult.success(user_badge)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
