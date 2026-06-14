# frozen_string_literal: true

module Commerce
  class SalesMetrics < ApplicationService
    def call
      paid_orders = Commerce::Order.where(status: %w[paid fulfilled refunded])
      revenue_cents = paid_orders.sum(:total_cents)
      pending_count = Commerce::Order.where(status: %w[pending awaiting_payment]).count
      low_stock = Commerce::Product.where(status: :active)
        .where.not(stock: nil)
        .where("stock <= ?", 5)
        .count

      ServiceResult.success(
        revenue_cents: revenue_cents,
        order_count: paid_orders.count,
        pending_count: pending_count,
        low_stock_count: low_stock
      )
    end
  end
end
