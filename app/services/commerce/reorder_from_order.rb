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
        next unless product&.active?

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
          skipped << product.name
        end
      end

      ServiceResult.success(cart: cart, added: added, skipped: skipped)
    end
  end
end
