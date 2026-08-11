# frozen_string_literal: true

require "digest"

module Community
  # Sends a Web Push message for a notification to the user's subscriptions.
  # Best-effort: dead subscriptions are pruned, all other errors swallowed so a
  # push failure never affects the notification itself.
  class DeliverWebPush < ApplicationService
    def initialize(notification:, delivery_key: nil)
      @notification = notification
      @delivery_key = delivery_key.to_s.presence
    end

    def call
      @notification = Notification.find_by(id: @notification.id)
      return ServiceResult.success(skipped: true) unless @notification

      @user = User.find_by(id: @notification.user_id)
      return ServiceResult.success(skipped: true) unless deliverable_notification?
      return ServiceResult.success(skipped: true) unless push_allowed?

      subscriptions = Community::PushSubscription.where(user_id: @user.id)
      return ServiceResult.success(skipped: true) if subscriptions.empty?

      payload = {
        title: @notification.title,
        body: @notification.body.to_s.truncate(140),
        path: @notification.destination_path,
        tag: delivery_tag
      }.to_json

      return capture(subscriptions, payload) if developer_mode_capture?

      subscriptions.find_each { |subscription| send_one(subscription, payload) }
      ServiceResult.success
    end

    private

    def delivery_tag
      return "mcweb-notification-#{@notification.id}" unless @delivery_key

      "mcweb-notification-#{Digest::SHA256.hexdigest(@delivery_key).first(24)}"
    end

    def deliverable_notification?
      @user&.session_eligible? &&
        Community::NotificationAccess.visible?(
          notification: @notification,
          user: @user
        )
    end

    def push_allowed?
      return false if @user.forum_dnd_until.present? && @user.forum_dnd_until > Time.current

      NotificationPreference.enabled?(@user, channel: "web_push", notification_type: @notification.notification_type)
    end

    def developer_mode_capture?
      defined?(Mcweb::DeveloperMode) &&
        Mcweb::DeveloperMode.enabled? &&
        Mcweb::DeveloperMode.integration(:web_push) == :capture
    end

    def capture(subscriptions, payload)
      subscription_count = 0
      captures = subscriptions.filter_map do |subscription|
        subscription_count += 1
        Mcweb::DeveloperModeCapture.capture_web_push!(
          notification_id: @notification.id,
          notification_type: @notification.notification_type,
          user_id: @user.id,
          subscription_id: subscription.id,
          endpoint: subscription.endpoint,
          payload: payload
        )
      end

      value = {
        captured: captures.length == subscription_count,
        capture_count: captures.length,
        subscription_count: subscription_count,
        capture_ids: captures.map(&:capture_id),
        capture_paths: captures.map { |entry| entry.path.to_s }.uniq
      }
      return ServiceResult.success(value) if value[:captured]

      ServiceResult.failure(code: "web_push_capture_failed", value: value)
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
