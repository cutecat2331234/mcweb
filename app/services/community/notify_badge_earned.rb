# frozen_string_literal: true

module Community
  class NotifyBadgeEarned < ApplicationService
    def initialize(user:, badge:)
      @user = user
      @badge = badge
    end

    def call
      return ServiceResult.success unless NotificationPreference.enabled?(@user, channel: "in_app", notification_type: "forum.badge")

      Notification.notify!(
        user: @user,
        notification_type: "forum.badge",
        title: "你获得了徽章：#{@badge.name}",
        body: @badge.description.to_s.truncate(120),
        metadata: {
          badge_slug: @badge.slug,
          path: "/app/forum/users/#{@user.username}"
        }
      )

      ServiceResult.success
    end
  end
end
