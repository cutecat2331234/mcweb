# frozen_string_literal: true

module Commerce
  class CompleteOrderPayment < ApplicationService
    def initialize(order:, from_status: nil, staff_marked: false)
      @order = order
      @from_status = from_status
      @staff_marked = staff_marked
    end

    def call
      Commerce::DebitGiftCard.call(order: @order)
      Commerce::DebitStoreCredit.call(order: @order)
      MailDeliveryJob.perform_later("Commerce::OrderMailer", "payment_confirmed", "deliver_now", args: [ @order.id ])
      Commerce::NotifyOrderEvent.call(
        user: @order.user,
        notification_type: "commerce.payment_confirmed",
        title: "支付成功",
        body: "订单 #{@order.order_number} 已支付成功。",
        path: "/store/orders/#{@order.public_id}"
      )
      Community::CheckAutoBadges.call(user: @order.user)
      @order.items.includes(:product).find_each do |item|
        next unless item.product

        Commerce::SubscribeProductDiscussion.call(user: @order.user, product: item.product)
      end
      Commerce::FulfillOrderJob.perform_later(@order.id)

      ServiceResult.success
    end
  end
end
