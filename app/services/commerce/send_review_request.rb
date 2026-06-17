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

      Commerce::NotifyOrderEvent.call(
        user: @order.user,
        notification_type: "commerce.review_request",
        title: "邀请你评价已购商品",
        body: "订单 #{@order.order_number} 已完成，欢迎分享购买体验。",
        path: "#{Mcweb::Paths::APP_PREFIX}/store/orders/#{@order.public_id}"
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
