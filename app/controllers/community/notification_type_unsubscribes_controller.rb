# frozen_string_literal: true

module Community
  class NotificationTypeUnsubscribesController < ApplicationController
    def show
      user_id, notification_type = Community::NotificationTypeUnsubscribeToken.verify(params[:token])
      user = User.find(user_id)
      NotificationPreference.set!(user, channel: "email", notification_type: notification_type, enabled: false)
      label = Community::NotificationTypeLabels.label_for(notification_type)
      redirect_to forum_preferences_path, notice: "已关闭 #{label} 邮件通知。"
    rescue Community::NotificationTypeUnsubscribeToken::InvalidToken, ActiveRecord::RecordNotFound
      redirect_to forum_preferences_path, alert: "退订链接无效或已过期。"
    end
  end
end
