# frozen_string_literal: true

module Commerce
  class SubscribeStockAlert < ApplicationService
    def initialize(user:, product:, variant: nil)
      @user = user
      @product = product
      @variant = variant
    end

    def call
      if @product.variants.exists? && @variant.nil?
        return ServiceResult.failure(error: "variant_required")
      end

      alert = Commerce::StockAlert.find_or_initialize_by(
        user: @user,
        product: @product,
        variant: @variant
      )
      alert.notified_at = nil
      alert.save!
      ServiceResult.success(alert)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
