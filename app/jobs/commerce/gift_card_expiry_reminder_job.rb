# frozen_string_literal: true

module Commerce
  class GiftCardExpiryReminderJob < ApplicationJob
    queue_as :mailers

    def perform
      window_start = 7.days.from_now.beginning_of_day
      window_end = 7.days.from_now.end_of_day

      Commerce::GiftCard
        .active_cards
        .where("balance_cents > 0")
        .where(expires_at: window_start..window_end)
        .find_each do |card|
          user = card.owner_user || card.created_by
          next unless user

          MailDeliveryJob.perform_later(
            "Commerce::GiftCardMailer",
            "expiry_reminder",
            "deliver_now",
            args: [ card.id, user.id ]
          )
        end
    end
  end
end
