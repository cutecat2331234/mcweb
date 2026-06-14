# frozen_string_literal: true

module Commerce
  class FulfillOrderJob < ApplicationJob
    queue_as :minecraft

    def perform(order_id)
      order = Commerce::Order.find(order_id)
      return unless order.status == "paid"

      if order.may_start_processing?
        order.start_processing!
        notify_processing!(order)
      end

      order.items.find_each do |order_item|
        result = Commerce::CreateFulfillment.call(order_item: order_item)
        next if result.failure?

        Minecraft::DispatchFulfillmentJob.perform_later(result.value.id)
      end

      order.reload
      if order.processing? && order.may_start_fulfilling?
        order.start_fulfilling!
        notify_fulfilling!(order)
      end
    end

    private

    def notify_processing!(order)
      Commerce::NotifyOrderEvent.call(
        user: order.user,
        notification_type: "commerce.order_processing",
        title: "订单处理中",
        body: "订单 #{order.order_number} 正在处理，请稍候。",
        path: "/store/orders/#{order.public_id}"
      )
    end

    def notify_fulfilling!(order)
      Commerce::NotifyOrderEvent.call(
        user: order.user,
        notification_type: "commerce.order_fulfilling",
        title: "订单发货中",
        body: "订单 #{order.order_number} 正在发货处理。",
        path: "/store/orders/#{order.public_id}"
      )
    end
  end
end
