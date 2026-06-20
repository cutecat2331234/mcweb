# frozen_string_literal: true

module Commerce
  class UpdateWishlistNote < ApplicationService
    def initialize(user:, product:, note:)
      @user = user
      @product = product
      @note = note.to_s.strip
    end

    def call
      item = Commerce::WishlistItem.find_by(user: @user, product: @product)
      return ServiceResult.failure(error: "wishlist_item_missing") unless item

      item.update!(note: @note.presence)
      ServiceResult.success(item: item)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
