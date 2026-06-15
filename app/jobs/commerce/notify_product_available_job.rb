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
            Notification.notify!(
              user: user,
              notification_type: "commerce.product_available",
              title: "商品已上架",
              body: "#{product.name} 现已开售，可以购买了。",
              metadata: {
                path: "/store/products/#{product.public_id}",
                product_id: product.public_id
              }
            )
          end

          alert.update!(notified_at: Time.current)
        end
    end
  end
end
