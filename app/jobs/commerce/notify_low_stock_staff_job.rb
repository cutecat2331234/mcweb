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
          title: Commerce::InAppNotification.t("low_stock_staff.title", product: product.name),
          body: Commerce::InAppNotification.t(variant_id ? "low_stock_staff_variant.body" : "low_stock_staff.body", product: product.name),
          metadata: {
            product_id: product.public_id,
            path: "/admin/store/products/#{product.public_id}"
          }
        )
      end
    end
  end
end
