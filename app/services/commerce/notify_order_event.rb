# frozen_string_literal: true

module Commerce
  class NotifyOrderEvent < ApplicationService
    def initialize(user:, notification_type:, title:, body:, path:, order_public_id: nil)
      @user = user
      @notification_type = notification_type
      @title = title
      @body = body
      @path = path
      @order_public_id = order_public_id.presence || extract_order_public_id(path)
    end

    def call
      return ServiceResult.success unless @user
      return ServiceResult.success unless NotificationPreference.enabled?(@user, channel: "in_app", notification_type: @notification_type)

      metadata = { path: @path }
      metadata[:order_public_id] = @order_public_id if @order_public_id.present?

      Commerce::InAppNotification.with_recipient_locale(@user) do
        Notification.notify!(
          user: @user,
          notification_type: @notification_type,
          title: resolve_value(@title),
          body: resolve_value(@body).to_s.truncate(200),
          metadata: metadata
        )
      end

      ServiceResult.success
    end

    private

    def resolve_value(value)
      value.respond_to?(:call) ? value.call : value
    end

    def extract_order_public_id(path)
      path.to_s[%r{/store/orders/(ord_[a-zA-Z0-9]+)}, 1]
    end
  end
end
