# frozen_string_literal: true

module Commerce
  class UnsubscribePriceAlert < ApplicationService
    def initialize(user:, product:)
      @user = user
      @product = product
    end

    def call
      alert = Commerce::PriceAlert.find_by(user: @user, product: @product)
      return ServiceResult.failure(error: "subscription_not_found") unless alert

      alert.destroy!
      ServiceResult.success
    end
  end
end
