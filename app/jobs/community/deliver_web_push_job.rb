# frozen_string_literal: true

module Community
  class DeliverWebPushJob < ApplicationJob
    queue_as :default

    def perform(notification_id)
      Community::DeliverWebPushForNotification.call(notification_id:)
    end
  end
end
