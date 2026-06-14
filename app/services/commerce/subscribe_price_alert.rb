# frozen_string_literal: true

module Commerce
  class SubscribePriceAlert < ApplicationService
    def initialize(user:, product:, variant: nil)
      @user = user
      @product = product
      @variant = variant
    end

    def call
      price_cents = @variant&.price_cents || @product.price_cents
      alert = Commerce::PriceAlert.find_or_initialize_by(user: @user, product: @product)
      alert.assign_attributes(variant: @variant, baseline_price_cents: price_cents, notified_at: nil)
      alert.save!
      ServiceResult.success(alert)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
