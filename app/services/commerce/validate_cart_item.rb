# frozen_string_literal: true

module Commerce
  class ValidateCartItem < ApplicationService
    def initialize(user:, product:, variant: nil, quantity: 1, cart: nil, replace_quantity: false)
      @user = user
      @product = product
      @variant = variant
      @cart = cart
      @replace_quantity = replace_quantity
      @quantity = quantity.to_i
    end

    def call
      @quantity = resolved_quantity
      return ServiceResult.failure(error: "数量至少为 1。") if @quantity < 1
      return ServiceResult.failure(error: "商品已下架。") unless @product.active?

      if @product.variants.exists? && @variant.nil?
        return ServiceResult.failure(error: "请选择规格。")
      end

      purchasable = @variant || @product
      if purchasable.stock.present? && purchasable.stock < @quantity
        return ServiceResult.failure(error: "库存不足。")
      end

      if @product.purchase_limit.present? && @user
        purchased = Commerce::OrderItem
          .joins(:order)
          .where(store_orders: { user_id: @user.id })
          .where.not(store_orders: { status: %w[cancelled failed refunded pending awaiting_payment] })
          .where(store_product_id: @product.id)
          .sum(:quantity)

        if purchased + @quantity > @product.purchase_limit
          return ServiceResult.failure(error: "已超过该商品的限购数量。")
        end
      end

      ServiceResult.success
    end

    private

    def resolved_quantity
      return @quantity if @replace_quantity || @cart.nil?

      existing = @cart.items.find_by(
        store_product_id: @product.id,
        store_product_variant_id: @variant&.id
      )
      (existing&.quantity || 0) + @quantity
    end
  end
end
