# frozen_string_literal: true

module Commerce
  class ToggleWishlist < ApplicationService
    def initialize(user:, product:, variant: nil)
      @user = user
      @product = product
      @variant = variant
    end

    def call
      item = Commerce::WishlistItem.find_by(user: @user, product: @product)
      if item
        if @variant.present? && item.variant_id != @variant.id
          item.update!(variant: @variant)
          ServiceResult.success(wishlisted: true, variant_id: @variant.id)
        else
          item.destroy!
          ServiceResult.success(wishlisted: false)
        end
      else
        Commerce::WishlistItem.create!(user: @user, product: @product, variant: @variant)
        ServiceResult.success(wishlisted: true, variant_id: @variant&.id)
      end
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
