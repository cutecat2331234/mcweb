# frozen_string_literal: true

module Commerce
  class NotifyOrderEvent < ApplicationService
    def initialize(user:, notification_type:, title:, body:, path:)
      @user = user
      @notification_type = notification_type
      @title = title
      @body = body
      @path = path
    end

    def call
      return ServiceResult.success unless @user
      return ServiceResult.success unless NotificationPreference.enabled?(@user, channel: "in_app", notification_type: @notification_type)

      Notification.notify!(
        user: @user,
        notification_type: @notification_type,
        title: @title,
        body: @body.truncate(200),
        metadata: { path: @path }
      )

      ServiceResult.success
    end
  end
end
