# frozen_string_literal: true

module Commerce
  class NotifyLowStockStaffJob < ApplicationJob
    queue_as :notifications

    def perform(product_id, variant_id = nil)
      product = Commerce::Product.find_by(id: product_id)
      return unless product&.active?

      low_stock = if variant_id
                    variant = product.variants.find_by(id: variant_id)
                    variant&.low_stock?
                  else
                    product.low_stock?
                  end
      return unless low_stock

      staff_ids = User.joins(roles: :permissions)
        .where(permissions: { key: "store.products.manage" })
        .distinct
        .pluck(:id)

      User.where(id: staff_ids).find_each do |user|
        next unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "commerce.low_stock")

        Notification.notify!(
          user: user,
          notification_type: "commerce.low_stock",
          title: "低库存提醒：#{product.name}",
          body: variant_id ? "变体库存紧张，请及时补货。" : "商品库存紧张，请及时补货。",
          metadata: {
            product_id: product.public_id,
            path: "/admin/store/products/#{product.public_id}"
          }
        )
      end
    end
  end
end
