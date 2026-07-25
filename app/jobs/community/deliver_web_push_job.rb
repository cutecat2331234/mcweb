# frozen_string_literal: true

module Community
  class DeliverWebPushJob < ApplicationJob
    queue_as :default

    def perform(notification_id)
      notification = Notification.find_by(id: notification_id)
      return unless notification
      user = User.find_by(id: notification.user_id)
      return unless user&.session_eligible?
      return unless Community::NotificationAccess.visible?(
        notification: notification,
        user: user
      )

      Community::DeliverWebPush.call(notification: notification)
    end
  end
end
