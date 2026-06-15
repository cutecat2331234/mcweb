# frozen_string_literal: true

module Commerce
  class EnsureCompareShareToken < ApplicationService
    def initialize(user:, product_ids: nil)
      @user = user
      @product_ids = product_ids
    end

    def call
      attrs = {}
      if @user.compare_share_token.blank?
        attrs[:compare_share_token] = SecureRandom.urlsafe_base64(16)
      end
      if @product_ids
        attrs[:compare_product_ids] = Array(@product_ids).map(&:to_s).uniq.first(Commerce::ToggleCompare.compare_max_items)
      end
      @user.update!(attrs) if attrs.any?

      ServiceResult.success(token: @user.compare_share_token, product_ids: @user.compare_product_ids)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
