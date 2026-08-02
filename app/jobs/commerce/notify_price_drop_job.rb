# frozen_string_literal: true

module Commerce
  class NotifyPriceDropJob < ApplicationJob
    queue_as :default

    def perform(product_id)
      product = Commerce::Product.find_by(id: product_id)
      return unless product&.active?

      Commerce::PriceAlert.where(store_product_id: product.id).includes(:user).find_each do |alert|
        current_price = alert.variant&.price_cents || product.price_cents
        next unless current_price < alert.baseline_price_cents

        user = alert.user
        next unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "commerce.price_drop")

        Commerce::InAppNotification.notify(
          user: user,
          notification_type: "commerce.price_drop",
          title_key: "price_drop.title",
          body_key: "price_drop.body",
          body_options: {
            product: product.name,
            current: -> { format_price(current_price, product.currency) },
            was: -> { format_price(alert.baseline_price_cents, product.currency) }
          },
          metadata: {
            path: "/app/store/products/#{product.public_id}",
            product_public_id: product.public_id
          }
        )

        if NotificationPreference.enabled?(user, channel: "email", notification_type: "commerce.price_drop")
          MailDeliveryJob.perform_later(
            "Commerce::OrderMailer",
            "price_drop",
            "deliver_now",
            args: [ user.id, product.id, alert.baseline_price_cents, current_price ]
          )
        end

        alert.update!(baseline_price_cents: current_price, notified_at: Time.current)
      end
    end

    private

    def format_price(cents, currency)
      ApplicationController.helpers.format_currency_from_cents(cents, currency)
    end
  end
end
