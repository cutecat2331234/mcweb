# frozen_string_literal: true

module Commerce
  class SendReviewRequest < ApplicationService
    def initialize(order:)
      @order = order
    end

    def call
      return ServiceResult.success(skipped: true) if @order.review_request_sent_at.present?
      return ServiceResult.success(skipped: true) unless @order.completed?

      reviewable = @order.items.joins(:product).where(store_products: { status: "active" }).exists?
      return ServiceResult.success(skipped: true) unless reviewable

      @order.update!(review_request_sent_at: Time.current)

      Commerce::InAppNotification.order_event(
        user: @order.user,
        notification_type: "commerce.review_request",
        key: "review_request",
        order: @order
      )

      if NotificationPreference.enabled?(@order.user, channel: "email", notification_type: "commerce.review_request")
        MailDeliveryJob.perform_later(
          "Commerce::OrderMailer",
          "review_request",
          "deliver_now",
          args: [ @order.id ]
        )
      end

      ServiceResult.success(sent: true)
    end
  end
end
