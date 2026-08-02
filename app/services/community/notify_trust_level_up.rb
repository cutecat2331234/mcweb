# frozen_string_literal: true

module Community
  class NotifyTrustLevelUp < ApplicationService
    def initialize(user:, level:)
      @user = user
      @level = level
    end

    def call
      email_enabled = Community::InstantEmailDelivery.allowed?(@user, notification_type: "forum.trust_level")
      in_app_enabled = NotificationPreference.enabled?(@user, channel: "in_app", notification_type: "forum.trust_level")
      return ServiceResult.success unless email_enabled || in_app_enabled

      if in_app_enabled
        level_name = Community::TrustLevel.localized_name(@level, locale: @user.locale)
        Community::InAppNotification.notify(
          user: @user,
          notification_type: "forum.trust_level",
          key: "trust_level_up",
          level_name: level_name,
          level: @level,
          metadata: {
            trust_level: @level,
            path: "#{Mcweb::Paths::APP_PREFIX}/forum/users/#{@user.username}"
          }
        )
      end

      if email_enabled
        MailDeliveryJob.perform_later(
          "Community::ForumMailer",
          "trust_level_up",
          "deliver_now",
          args: [ @user.id, @level ]
        )
      end

      ServiceResult.success
    end
  end
end
