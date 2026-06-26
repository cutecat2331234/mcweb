# frozen_string_literal: true

module Community
  # Sends a Web Push message for a notification to the user's subscriptions.
  # Best-effort: dead subscriptions are pruned, all other errors swallowed so a
  # push failure never affects the notification itself.
  class DeliverWebPush < ApplicationService
    def initialize(notification:)
      @notification = notification
      @user = notification.user
    end

    def call
      return ServiceResult.success(skipped: true) unless push_allowed?

      subscriptions = Community::PushSubscription.where(user_id: @user.id)
      return ServiceResult.success(skipped: true) if subscriptions.empty?

      payload = {
        title: @notification.title,
        body: @notification.body.to_s.truncate(140),
        path: @notification.destination_path,
        tag: "mcweb-notification-#{@notification.id}"
      }.to_json

      subscriptions.find_each { |subscription| send_one(subscription, payload) }
      ServiceResult.success
    end

    private

    def push_allowed?
      return false if @user.forum_dnd_until.present? && @user.forum_dnd_until > Time.current

      NotificationPreference.enabled?(@user, channel: "web_push", notification_type: @notification.notification_type)
    end

    def send_one(subscription, payload)
      WebPush.payload_send(
        message: payload,
        endpoint: subscription.endpoint,
        p256dh: subscription.p256dh_key,
        auth: subscription.auth_key,
        vapid: {
          public_key: Community::VapidKeys.public_key,
          private_key: Community::VapidKeys.private_key,
          subject: "mailto:webpush@mcweb.local"
        }
      )
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
      subscription.destroy
    rescue StandardError
      nil
    end
  end
end
