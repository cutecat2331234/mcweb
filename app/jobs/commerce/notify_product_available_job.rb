# frozen_string_literal: true

module Commerce
  class NotifyProductAvailableJob < ApplicationJob
    queue_as :mailers

    def perform(product_id)
      product = Commerce::Product.find_by(id: product_id)
      return unless product&.active?
      return if product.coming_soon?

      Commerce::ProductAvailabilityAlert
        .where(store_product_id: product.id, notified_at: nil)
        .includes(:user)
        .find_each do |alert|
          user = alert.user

          if NotificationPreference.enabled?(user, channel: "in_app", notification_type: "commerce.product_available")
            Commerce::InAppNotification.product_event(
              user: user,
              notification_type: "commerce.product_available",
              key: "product_available",
              product: product,
              path: "#{Mcweb::Paths::APP_PREFIX}/store/products/#{product.public_id}"
            )
          end

          if NotificationPreference.enabled?(user, channel: "email", notification_type: "commerce.product_available")
            MailDeliveryJob.perform_later(
              "Commerce::AvailabilityMailer",
              "product_available",
              "deliver_now",
              args: [ alert.id ]
            )
          end

          alert.update!(notified_at: Time.current)
        end
    end
  end
end
