# frozen_string_literal: true

module Community
  class NotifyBadgeEarned < ApplicationService
    def initialize(user:, badge:)
      @user = user
      @badge = badge
    end

    def call
      email_enabled = NotificationPreference.enabled?(@user, channel: "email", notification_type: "forum.badge")
      in_app_enabled = NotificationPreference.enabled?(@user, channel: "in_app", notification_type: "forum.badge")
      return ServiceResult.success unless email_enabled || in_app_enabled

      if in_app_enabled
        Notification.notify!(
          user: @user,
          notification_type: "forum.badge",
          title: "你获得了徽章：#{@badge.name}",
          body: @badge.description.to_s.truncate(120),
          metadata: {
            badge_slug: @badge.slug,
            path: "/forum/badges/#{@badge.slug}"
          }
        )
      end

      if email_enabled
        MailDeliveryJob.perform_later(
          "Community::ForumMailer",
          "badge_earned",
          "deliver_now",
          args: [ @user.id, @badge.id ]
        )
      end

      ServiceResult.success
    end
  end
end
