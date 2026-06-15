# frozen_string_literal: true

module Commerce
  class PurchaseLimitRemaining < ApplicationService
    def initialize(user:, product:)
      @user = user
      @product = product
    end

    def call
      return ServiceResult.success(remaining: nil) unless @user && @product.purchase_limit.present?

      purchased = Commerce::OrderItem
        .joins(:order)
        .where(store_orders: { user_id: @user.id })
        .where.not(store_orders: { status: %w[cancelled failed refunded] })
        .where(store_product_id: @product.id)
        .sum(:quantity)

      remaining = [ @product.purchase_limit - purchased, 0 ].max
      ServiceResult.success(remaining: remaining, purchased: purchased, limit: @product.purchase_limit)
    end
  end
end
