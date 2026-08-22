# frozen_string_literal: true

module Community
  class DeliverWebPushForNotification < ApplicationService
    def initialize(notification_id:, delivery_key: nil)
      @notification_id = notification_id
      @delivery_key = delivery_key.to_s.presence
    end

    def call
      notification = Notification.find_by(id: @notification_id)
      return skipped("source_missing") unless notification

      user = User.find_by(id: notification.user_id)
      unless user&.session_eligible? && Account::NotificationAccess.visible?(
        notification:,
        user:
      )
        return skipped("delivery_not_allowed")
      end

      result = Community::DeliverWebPush.call(notification:, delivery_key: @delivery_key)
      return result if result.failure?
      return skipped("delivery_not_allowed") if result.value.to_h[:skipped]

      ServiceResult.success
    end

    private

    def skipped(reason_code)
      ServiceResult.success(skipped: true, reason_code:)
    end
  end
end
