# frozen_string_literal: true

module Community
  class NotifyTrustLevelUp < ApplicationService
    def initialize(user:, level:, level_name:)
      @user = user
      @level = level
      @level_name = level_name
    end

    def call
      email_enabled = Community::InstantEmailDelivery.allowed?(@user, notification_type: "forum.trust_level")
      in_app_enabled = NotificationPreference.enabled?(@user, channel: "in_app", notification_type: "forum.trust_level")
      return ServiceResult.success unless email_enabled || in_app_enabled

      if in_app_enabled
        Notification.notify!(
          user: @user,
          notification_type: "forum.trust_level",
          title: "信任等级提升：#{@level_name}",
          body: "你已达到信任等级 #{@level}，解锁更多社区权限。",
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
          args: [ @user.id, @level, @level_name ]
        )
      end

      ServiceResult.success
    end
  end
end
