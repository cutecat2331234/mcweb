# frozen_string_literal: true

module Community
  class NotifyUserWarning < ApplicationService
    def initialize(warning:)
      @warning = warning
      @user = warning.user
    end

    def call
      return ServiceResult.success unless NotificationPreference.enabled?(@user, channel: "in_app", notification_type: "forum.user_warning")

      Community::InAppNotification.notify(
        user: @user,
        notification_type: "forum.user_warning",
        key: "user_warning",
        reason: @warning.reason.truncate(200),
        metadata: {
          path: "/app/forum/users/#{@user.username}",
          warning_id: @warning.id,
          points: @warning.points
        }
      )

      if NotificationPreference.enabled?(@user, channel: "email", notification_type: "forum.user_warning")
        MailDeliveryJob.perform_later(
          "Community::ForumMailer",
          "user_warning",
          "deliver_now",
          args: [ @user.id, @warning.id ]
        )
      end

      ServiceResult.success
    end
  end
end
