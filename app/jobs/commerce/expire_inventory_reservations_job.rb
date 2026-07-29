# frozen_string_literal: true

module Commerce
  class ExpireInventoryReservationsJob < ApplicationJob
    queue_as :maintenance

    def perform
      InventoryReservation.due.distinct.pluck(:store_order_id).each do |order_id|
        order = Order.find_by(id: order_id)
        next unless order&.pending? || order&.awaiting_payment?

        result = CancelOrder.call(order:, reason: "inventory_reservation_expired")
        Rails.logger.warn("inventory reservation expiry failed for order #{order.id}") if result.failure?
      end
    end
  end
end
