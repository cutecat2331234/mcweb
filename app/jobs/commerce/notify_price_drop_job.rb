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

        Notification.notify!(
          user: user,
          notification_type: "commerce.price_drop",
          title: "商品降价了",
          body: "#{product.name} 现价 #{format_price(current_price, product.currency)}（原价 #{format_price(alert.baseline_price_cents, product.currency)}）",
          metadata: {
            path: "/store/products/#{product.public_id}",
            product_public_id: product.public_id
          }
        )

        alert.update!(baseline_price_cents: current_price, notified_at: Time.current)
      end
    end

    private

    def format_price(cents, currency)
      unit = currency == "CNY" ? "¥" : "$"
      ActionController::Base.helpers.number_to_currency(cents / 100.0, unit: unit)
    end
  end
end
