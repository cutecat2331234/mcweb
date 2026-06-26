# frozen_string_literal: true

module Community
  class DeliverWebPushJob < ApplicationJob
    queue_as :default

    def perform(notification_id)
      notification = Notification.find_by(id: notification_id)
      return unless notification

      Community::DeliverWebPush.call(notification: notification)
    end
  end
end
