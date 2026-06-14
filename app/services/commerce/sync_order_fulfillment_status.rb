# frozen_string_literal: true

module Commerce
  class SyncOrderFulfillmentStatus < ApplicationService
    def initialize(order:)
      @order = order
    end

    def call
      return ServiceResult.success(@order) if @order.fulfilled? || @order.completed?

      item_count = @order.items.count
      return ServiceResult.success(@order) if item_count.zero?

      fulfilled_count = @order.fulfillments.where(status: "fulfilled").count
      return ServiceResult.success(@order) unless fulfilled_count >= item_count

      was_paid = @order.paid?
      if @order.may_mark_fulfilled?
        @order.mark_fulfilled!
      elsif @order.paid?
        @order.update!(status: "fulfilled")
      end

      if was_paid && @order.fulfilled?
        MailDeliveryJob.perform_later("Commerce::OrderMailer", "order_fulfilled", "deliver_now", args: [ @order.id ])
        Commerce::NotifyOrderEvent.call(
          user: @order.user,
          notification_type: "commerce.order_fulfilled",
          title: "订单已发货",
          body: "订单 #{@order.order_number} 商品已发货完成。",
          path: "/store/orders/#{@order.public_id}"
        )
      end

      ServiceResult.success(@order)
    rescue AASM::InvalidTransition => e
      ServiceResult.failure(error: e.message)
    end
  end
end
