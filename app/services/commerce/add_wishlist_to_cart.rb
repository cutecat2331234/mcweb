# frozen_string_literal: true

module Commerce
  class AddWishlistToCart < ApplicationService
    def initialize(user:)
      @user = user
    end

    def call
      cart = Commerce::Cart.find_or_create_by!(user: @user)
      added = 0
      skipped = []

      Commerce::WishlistItem.where(user: @user).includes(:product).find_each do |item|
        product = item.product
        next unless product.active? && product.in_stock?

        variant = if product.variants.exists?
                    product.variants.order(:id).find { |v| v.stock.nil? || v.stock.positive? }
                  end
        next if product.variants.exists? && variant.nil?

        validation = Commerce::ValidateCartItem.call(
          user: @user,
          product: product,
          variant: variant,
          quantity: 1,
          cart: cart
        )

        if validation.success?
          cart.add_item!(product: product, variant: variant, quantity: 1)
          added += 1
        else
          skipped << product.name
        end
      end

      ServiceResult.success(cart: cart, added: added, skipped: skipped)
    end
  end
end
