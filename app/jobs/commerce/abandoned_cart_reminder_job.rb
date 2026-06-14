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
          next unless NotificationPreference.enabled?(user, channel: "email", notification_type: "commerce.abandoned_cart")

          MailDeliveryJob.perform_later("Commerce::CartMailer", "abandoned_cart", "deliver_now", args: [ cart.id ])
          cart.update_column(:abandoned_reminder_sent_at, Time.current)
        end
    end
  end
end
