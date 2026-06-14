# frozen_string_literal: true

module Commerce
  class SalesMetrics < ApplicationService
    def call
      paid_orders = Commerce::Order.where(status: %w[paid fulfilled refunded])
      revenue_cents = paid_orders.sum(:total_cents)
      pending_count = Commerce::Order.where(status: %w[pending awaiting_payment]).count
      low_stock = low_stock_product_count + low_stock_variant_count

      ServiceResult.success(
        revenue_cents: revenue_cents,
        order_count: paid_orders.count,
        pending_count: pending_count,
        low_stock_count: low_stock
      )
    end

    private

    def low_stock_product_count
      Commerce::Product.where(status: :active)
        .where.not(stock: nil)
        .where("stock <= ?", 5)
        .count
    end

    def low_stock_variant_count
      Commerce::ProductVariant.joins(:product)
        .where(store_products: { status: :active })
        .where.not(stock: nil)
        .where("store_product_variants.stock <= ?", 5)
        .count
    end
  end
end
