# frozen_string_literal: true

module Commerce
  class SalesMetrics < ApplicationService
    LOW_STOCK_THRESHOLD = 5

    def call
      paid_orders = Commerce::Order.where(status: %w[paid fulfilled refunded])
      revenue_cents = paid_orders.sum(:total_cents)
      pending_count = Commerce::Order.where(status: %w[pending awaiting_payment]).count
      low_stock = low_stock_product_count + low_stock_variant_count
      week_ago = 7.days.ago
      revenue_7d_cents = paid_orders.where("created_at >= ?", week_ago).sum(:total_cents)
      refund_count = Commerce::Refund.where(status: %w[pending completed]).where("created_at >= ?", week_ago).count
      abandoned_carts = Commerce::Cart.where.not(user_id: nil).joins(:items).where("store_carts.updated_at < ?", 24.hours.ago).distinct.count
      order_count = paid_orders.count
      aov_cents = order_count.positive? ? (revenue_cents / order_count) : 0

      ServiceResult.success(
        revenue_cents: revenue_cents,
        revenue_7d_cents: revenue_7d_cents,
        order_count: order_count,
        pending_count: pending_count,
        low_stock_count: low_stock,
        refund_count_7d: refund_count,
        abandoned_carts_count: abandoned_carts,
        aov_cents: aov_cents
      )
    end

    private

    def low_stock_product_count
      Commerce::Product.where(status: :active)
        .where.not(stock: nil)
        .where("stock <= ?", LOW_STOCK_THRESHOLD)
        .count
    end

    def low_stock_variant_count
      Commerce::ProductVariant.joins(:product)
        .where(store_products: { status: :active })
        .where.not(stock: nil)
        .where("store_product_variants.stock <= ?", LOW_STOCK_THRESHOLD)
        .count
    end
  end
end
