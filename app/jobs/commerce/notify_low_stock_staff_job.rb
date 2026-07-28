# frozen_string_literal: true

module Commerce
  class NotifyLowStockStaffJob < ApplicationJob
    queue_as :notifications

    PERMISSION_KEYS = %w[store.products.read store.products.manage].freeze

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

      recipients.find_each do |user|
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

    private

    def recipients
      role_user_ids = User.joins(roles: :permissions)
        .where(permissions: { key: PERMISSION_KEYS })
        .select(:id)
      group_user_ids = Community::GroupMembership
        .joins(:user_group)
        .where(
          "community_user_groups.permissions @> ?::jsonb " \
          "OR community_user_groups.permissions @> ?::jsonb",
          [ PERMISSION_KEYS.first ].to_json,
          [ PERMISSION_KEYS.last ].to_json
        )
        .select(:user_id)

      User.where(account_type: "owner")
        .or(User.where(id: role_user_ids))
        .or(User.where(id: group_user_ids))
        .distinct
    end
  end
end
