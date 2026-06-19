# frozen_string_literal: true

module Community
  class NotificationTypeUnsubscribesController < ApplicationController
    def show
      user_id, notification_type = Community::NotificationTypeUnsubscribeToken.verify(params[:token])
      user = User.find(user_id)
      NotificationPreference.set!(user, channel: "email", notification_type: notification_type, enabled: false)
      label = Community::NotificationTypeLabels.label_for(notification_type)
      redirect_to forum_preferences_path, notice: t("mcweb.flash.notification_email_unsubscribed", label: label)
    rescue Community::NotificationTypeUnsubscribeToken::InvalidToken, ActiveRecord::RecordNotFound
      redirect_to forum_preferences_path, alert: t("mcweb.flash.unsubscribe_invalid")
    end
  end
end
