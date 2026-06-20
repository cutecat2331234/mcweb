# frozen_string_literal: true

module Commerce
  class ExpirePendingOrdersJob < ApplicationJob
    queue_as :maintenance

    def perform
      Commerce::Order.where(status: %w[pending awaiting_payment]).find_each do |order|
        next unless order.payment_expired?

        result = Commerce::CancelOrder.call(order: order, reason: "expired")
        unless result.success?
          Rails.logger.warn("[ExpirePendingOrdersJob] Failed to cancel order #{order.id}: #{result.error}")
        end
      end
    end
  end
end
