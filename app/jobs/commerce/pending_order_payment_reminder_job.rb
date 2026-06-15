# frozen_string_literal: true

module Commerce
  class PendingOrderPaymentReminderJob < ApplicationJob
    queue_as :mailers

    def perform
      window = expiry_window
      reminder_after = window / 2

      Commerce::Order
        .where(status: %w[pending awaiting_payment])
        .where(payment_reminder_sent_at: nil)
        .where("created_at < ?", reminder_after.ago)
        .where("created_at > ?", window.ago)
        .includes(:user)
        .find_each do |order|
          deliver_reminder(order)
          order.update_column(:payment_reminder_sent_at, Time.current)
        end
    end

    private

    def expiry_window
      minutes = SiteSetting.get("store.pending_order_expiry_minutes", "30").to_i
      minutes = 30 if minutes <= 0
      minutes.minutes
    end

    def deliver_reminder(order)
      user = order.user
      return unless user

      email_enabled = NotificationPreference.enabled?(user, channel: "email", notification_type: "commerce.payment_reminder")
      in_app_enabled = NotificationPreference.enabled?(user, channel: "in_app", notification_type: "commerce.payment_reminder")
      return unless email_enabled || in_app_enabled

      if email_enabled
        MailDeliveryJob.perform_later(
          "Commerce::OrderMailer",
          "payment_reminder",
          "deliver_now",
          args: [ order.id ]
        )
      end

      return unless in_app_enabled

      expires_label = payment_expires_label(order)
      Commerce::NotifyOrderEvent.call(
        user: user,
        notification_type: "commerce.payment_reminder",
        title: "订单待支付提醒",
        body: "订单 #{order.order_number} 请在 #{expires_label} 前完成支付。",
        path: "/store/orders/#{order.public_id}"
      )
    end

    def payment_expires_label(order)
      minutes = SiteSetting.get("store.pending_order_expiry_minutes", "30").to_i
      minutes = 30 if minutes <= 0
      expires = order.created_at + minutes.minutes
      I18n.l(expires, format: :short)
    end
  end
end
