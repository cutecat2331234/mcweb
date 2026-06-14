# frozen_string_literal: true

module Commerce
  class ToggleWishlist < ApplicationService
    def initialize(user:, product:)
      @user = user
      @product = product
    end

    def call
      item = Commerce::WishlistItem.find_by(user: @user, product: @product)
      if item
        item.destroy!
        ServiceResult.success(wishlisted: false)
      else
        Commerce::WishlistItem.create!(user: @user, product: @product)
        ServiceResult.success(wishlisted: true)
      end
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
