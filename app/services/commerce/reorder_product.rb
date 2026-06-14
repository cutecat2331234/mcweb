# frozen_string_literal: true

module Commerce
  class ReorderProduct < ApplicationService
    def initialize(user:, product:)
      @user = user
      @product = product
    end

    def call
      item = Commerce::OrderItem
        .joins(:order)
        .where(store_orders: { user_id: @user.id, status: %w[paid processing fulfilling fulfilled completed] })
        .where(store_product_id: @product.id)
        .order("store_orders.created_at DESC")
        .first

      return ServiceResult.failure(error: "未找到可再次购买的订单记录。") unless item

      cart = Commerce::Cart.find_or_create_by!(user: @user)
      validation = Commerce::ValidateCartItem.call(
        user: @user,
        product: @product,
        variant: item.variant,
        quantity: 1,
        cart: cart
      )
      return validation unless validation.success?

      cart.add_item!(product: @product, variant: item.variant, quantity: 1)
      ServiceResult.success(cart)
    end
  end
end
