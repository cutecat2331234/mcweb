# frozen_string_literal: true

module Commerce
  class FulfillOrderJob < ApplicationJob
    queue_as :minecraft

    def perform(order_id)
      order = Commerce::Order.find(order_id)
      return unless order.status == "paid"

      order.items.find_each do |order_item|
        result = Commerce::CreateFulfillment.call(order_item: order_item)
        next if result.failure?

        Minecraft::DispatchFulfillmentJob.perform_later(result.value.id)
      end
    end
  end
end
