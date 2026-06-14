# frozen_string_literal: true

module Community
  class NotifyTrustLevelUp < ApplicationService
    def initialize(user:, level:, level_name:)
      @user = user
      @level = level
      @level_name = level_name
    end

    def call
      return ServiceResult.success unless NotificationPreference.enabled?(@user, channel: "in_app", notification_type: "forum.trust_level")

      Notification.notify!(
        user: @user,
        notification_type: "forum.trust_level",
        title: "信任等级提升：#{@level_name}",
        body: "你已达到信任等级 #{@level}，解锁更多社区权限。",
        metadata: {
          trust_level: @level,
          path: "/forum/users/#{@user.username}"
        }
      )

      ServiceResult.success
    end
  end
end
