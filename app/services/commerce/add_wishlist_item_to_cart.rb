# frozen_string_literal: true

module Commerce
  class AddWishlistItemToCart < ApplicationService
    def initialize(user:, product:)
      @user = user
      @product = product
    end

    def call
      item = Commerce::WishlistItem.find_by(user: @user, product: @product)
      return ServiceResult.failure(error: "wishlist_item_missing") unless item

      product = item.product
      return ServiceResult.failure(error: "product_inactive") unless product.active?

      variant = item.variant
      if variant.nil? && product.variants.exists?
        variant = product.variants.order(:id).find { |entry| entry.stock.nil? || entry.stock.positive? }
      end
      return ServiceResult.failure(error: "variant_required") if product.variants.exists? && variant.nil?

      cart = Commerce::Cart.find_or_create_by!(user: @user)
      validation = Commerce::ValidateCartItem.call(
        user: @user,
        product: product,
        variant: variant,
        quantity: 1,
        cart: cart
      )
      return validation unless validation.success?

      cart.add_item!(product: product, variant: variant, quantity: 1)
      ServiceResult.success(cart: cart)
    end
  end
end
