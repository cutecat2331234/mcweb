# frozen_string_literal: true

module Commerce
  class NotifyStockRestockedJob < ApplicationJob
    queue_as :mailers

    def perform(product_id, variant_id = nil)
      product = Commerce::Product.find_by(id: product_id)
      return unless product&.active?

      purchasable = variant_id ? product.variants.find_by(id: variant_id) : product
      return unless purchasable
      return unless purchasable.stock.nil? || purchasable.stock.positive?

      scope = Commerce::StockAlert.where(store_product_id: product.id, notified_at: nil)
      scope = scope.where(store_product_variant_id: variant_id) if variant_id

      scope.includes(:user).find_each do |alert|
        user = alert.user

        if NotificationPreference.enabled?(user, channel: "in_app", notification_type: "commerce.stock_restocked")
          Notification.notify!(
            user: user,
            notification_type: "commerce.stock_restocked",
            title: Commerce::InAppNotification.t("stock_restocked.title", product: product.name),
            body: if alert.variant
                    Commerce::InAppNotification.t(
                      "stock_restocked_variant.body",
                      product: product.name,
                      variant: alert.variant.name
                    )
                  else
                    Commerce::InAppNotification.t("stock_restocked.body", product: product.name)
                  end,
            metadata: {
              path: "/app/store/products/#{product.public_id}",
              product_id: product.public_id,
              variant_id: alert.variant&.id
            }
          )
        end

        if NotificationPreference.enabled?(user, channel: "email", notification_type: "commerce.stock_restocked")
          MailDeliveryJob.perform_later(
            "Commerce::StockMailer",
            "restocked",
            "deliver_now",
            args: [ alert.id ]
          )
        end

        alert.update!(notified_at: Time.current)
      end
    end
  end
end
