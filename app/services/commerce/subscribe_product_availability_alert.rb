# frozen_string_literal: true

module Commerce
  class SubscribeProductAvailabilityAlert < ApplicationService
    def initialize(user:, product:)
      @user = user
      @product = product
    end

    def call
      return ServiceResult.failure(error: "product_already_available") unless @product.coming_soon?

      alert = Commerce::ProductAvailabilityAlert.find_or_initialize_by(user: @user, product: @product)
      alert.notified_at = nil
      alert.save!
      ServiceResult.success(alert)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
