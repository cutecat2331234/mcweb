# frozen_string_literal: true

module Commerce
  class ReorderFromOrder < ApplicationService
    def initialize(user:, order:)
      @user = user
      @order = order
    end

    def call
      cart = Commerce::Cart.find_or_create_by!(user: @user)
      added = 0
      skipped = []

      @order.items.includes(:product, :variant).find_each do |item|
        product = item.product
        unless product&.active?
          skipped << { name: item.product_name, reason: "商品已下架。" }
          next
        end

        validation = Commerce::ValidateCartItem.call(
          user: @user,
          product: product,
          variant: item.variant,
          quantity: item.quantity,
          cart: cart
        )

        if validation.success?
          cart.add_item!(product: product, variant: item.variant, quantity: item.quantity)
          added += 1
        else
          reason = validation.error.presence || "无法加入购物车"
          skipped << { name: product.name, reason: reason }
        end
      end

      ServiceResult.success(cart: cart, added: added, skipped: skipped, skipped_names: skipped.map { |entry| entry[:name] })
    end
  end
end
