# frozen_string_literal: true

module Commerce
  class MoveCartItemToWishlist < ApplicationService
    def initialize(user:, cart_item:)
      @user = user
      @cart_item = cart_item
    end

    def call
      return ServiceResult.failure(error: "请先登录。") unless @user
      return ServiceResult.failure(error: "购物车项不存在。") unless @cart_item

      Commerce::ToggleWishlist.call(
        user: @user,
        product: @cart_item.product,
        variant: @cart_item.variant
      )

      @cart_item.destroy!
      @cart_item.cart.reset_abandoned_reminder!

      ServiceResult.success
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
