# frozen_string_literal: true

module Commerce
  class ValidateCartItem < ApplicationService
    def initialize(user:, product:, variant: nil, quantity: 1)
      @user = user
      @product = product
      @variant = variant
      @quantity = quantity.to_i
    end

    def call
      return ServiceResult.failure(error: "Quantity must be at least 1.") if @quantity < 1
      return ServiceResult.failure(error: "Product is not available.") unless @product.active?

      purchasable = @variant || @product
      if purchasable.stock.present? && purchasable.stock < @quantity
        return ServiceResult.failure(error: "Insufficient stock.")
      end

      if @product.purchase_limit.present? && @user
        purchased = Commerce::OrderItem
          .joins(:order)
          .where(store_orders: { user_id: @user.id })
          .where.not(store_orders: { status: %w[cancelled failed refunded] })
          .where(store_product_id: @product.id)
          .sum(:quantity)

        if purchased + @quantity > @product.purchase_limit
          return ServiceResult.failure(error: "Purchase limit exceeded for this product.")
        end
      end

      ServiceResult.success
    end
  end
end
