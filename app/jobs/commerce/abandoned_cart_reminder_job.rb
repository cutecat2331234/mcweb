# frozen_string_literal: true

module Commerce
  class AbandonedCartReminderJob < ApplicationJob
    queue_as :mailers

    REMINDER_AFTER = 24.hours

    def perform
      Commerce::Cart.where.not(user_id: nil)
        .where(abandoned_reminder_sent_at: nil)
        .includes(:items, :user)
        .find_each do |cart|
          next if cart.empty?
          next if cart.updated_at > REMINDER_AFTER.ago

          user = cart.user
          next unless user

          email_enabled = NotificationPreference.enabled?(user, channel: "email", notification_type: "commerce.abandoned_cart")
          in_app_enabled = NotificationPreference.enabled?(user, channel: "in_app", notification_type: "commerce.abandoned_cart")

          next unless email_enabled || in_app_enabled

          MailDeliveryJob.perform_later("Commerce::CartMailer", "abandoned_cart", "deliver_now", args: [ cart.id ]) if email_enabled

          if in_app_enabled
            item_count = cart.items.sum(:quantity)
            Commerce::NotifyOrderEvent.call(
              user: user,
              notification_type: "commerce.abandoned_cart",
              title: "购物车提醒",
              body: "你的购物车中有 #{item_count} 件商品尚未结账。",
              path: "/store/cart"
            )
          end

          cart.update_column(:abandoned_reminder_sent_at, Time.current)
        end
    end
  end
end
