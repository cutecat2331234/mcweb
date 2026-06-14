# frozen_string_literal: true

module Commerce
  class EnsureWishlistShareToken < ApplicationService
    def initialize(user:)
      @user = user
    end

    def call
      if @user.wishlist_share_token.blank?
        @user.update!(wishlist_share_token: SecureRandom.urlsafe_base64(16))
      end
      ServiceResult.success(token: @user.wishlist_share_token)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
