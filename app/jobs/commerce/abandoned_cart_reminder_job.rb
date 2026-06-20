# frozen_string_literal: true

module Commerce
  class AbandonedCartReminderJob < ApplicationJob
    queue_as :mailers

    FIRST_REMINDER_AFTER = 24.hours
    SECOND_REMINDER_AFTER = 72.hours

    def perform
      send_first_reminders
      send_second_reminders
    end

    private

    def send_first_reminders
      Commerce::Cart.where.not(user_id: nil)
        .where(abandoned_reminder_sent_at: nil)
        .includes(:items, :user)
        .find_each do |cart|
          next if cart.empty?
          next if cart.updated_at > FIRST_REMINDER_AFTER.ago

          deliver_reminder(cart, second: false)
          cart.update_column(:abandoned_reminder_sent_at, Time.current)
        end
    end

    def send_second_reminders
      Commerce::Cart.where.not(user_id: nil)
        .where.not(abandoned_reminder_sent_at: nil)
        .where(abandoned_second_reminder_sent_at: nil)
        .includes(:items, :user)
        .find_each do |cart|
          next if cart.empty?
          next if cart.updated_at > SECOND_REMINDER_AFTER.ago
          next unless cart.abandoned_reminder_sent_at&.< SECOND_REMINDER_AFTER.ago

          deliver_reminder(cart, second: true)
          cart.update_column(:abandoned_second_reminder_sent_at, Time.current)
        end
    end

    def deliver_reminder(cart, second:)
      user = cart.user
      return unless user

      email_enabled = NotificationPreference.enabled?(user, channel: "email", notification_type: "commerce.abandoned_cart")
      in_app_enabled = NotificationPreference.enabled?(user, channel: "in_app", notification_type: "commerce.abandoned_cart")
      return unless email_enabled || in_app_enabled

      coupon_code = SiteSetting.get("store.abandoned_cart_coupon_code", "").to_s.strip.presence
      if email_enabled
        MailDeliveryJob.perform_later(
          "Commerce::CartMailer",
          "abandoned_cart",
          "deliver_now",
          args: [ cart.id, second, coupon_code ]
        )
      end

      if in_app_enabled
        item_count = cart.items.sum(:quantity)
        cart.ensure_recovery_token!
        recovery_path = "#{Mcweb::Paths::APP_PREFIX}/store/cart?recovery=#{cart.recovery_token}"
        recovery_path += "&coupon=#{ERB::Util.url_encode(coupon_code)}" if coupon_code.present?
        key = second ? "abandoned_cart_followup" : "abandoned_cart"
        Commerce::NotifyOrderEvent.call(
          user: user,
          notification_type: "commerce.abandoned_cart",
          title: Commerce::InAppNotification.t("#{key}.title"),
          body: Commerce::InAppNotification.t("#{key}.body", count: item_count),
          path: recovery_path
        )
      end
    end
  end
end
