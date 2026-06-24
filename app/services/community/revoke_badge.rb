# frozen_string_literal: true

module Community
  # Admin un-grant of a badge from a user (mirror of AwardBadge). Idempotent:
  # revoking a badge the user doesn't hold succeeds as a no-op.
  class RevokeBadge < ApplicationService
    def initialize(user:, badge_slug:)
      @user = user
      @badge_slug = badge_slug.to_s
    end

    def call
      badge = Community::Badge.find_by(slug: @badge_slug)
      return ServiceResult.failure(error: "Badge not found.") unless badge

      user_badge = Community::UserBadge.find_by(user: @user, badge: badge)
      user_badge&.destroy!

      ServiceResult.success(badge)
    end
  end
end
