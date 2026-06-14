# frozen_string_literal: true

module Commerce
  class NotifyProductChangelogJob < ApplicationJob
    queue_as :default

    def perform(product_id)
      product = Commerce::Product.find_by(id: product_id)
      return unless product&.active?
      return if product.changelog.blank?

      version_key = product.version.presence || product.updated_at.to_i.to_s
      return if product.changelog_notified_version == version_key

      buyer_ids = Commerce::OrderItem
        .joins(:order)
        .where(store_product_id: product.id)
        .where(store_orders: { status: %w[paid processing fulfilling fulfilled completed] })
        .distinct
        .pluck("store_orders.user_id")

      User.where(id: buyer_ids).find_each do |user|
        next unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "commerce.product_changelog")

        Notification.notify!(
          user: user,
          notification_type: "commerce.product_changelog",
          title: "商品更新：#{product.name}",
          body: product.changelog.truncate(200),
          metadata: {
            path: "/store/products/#{product.public_id}",
            product_public_id: product.public_id
          }
        )

        if NotificationPreference.enabled?(user, channel: "email", notification_type: "commerce.product_changelog")
          MailDeliveryJob.perform_later(
            "Commerce::OrderMailer",
            "product_changelog",
            "deliver_now",
            args: [ user.id, product.id ]
          )
        end
      end

      product.update_column(:changelog_notified_version, version_key)
    end
  end
end
