# frozen_string_literal: true

module Commerce
  class UnsubscribeProductAvailabilityAlert < ApplicationService
    def initialize(user:, product:)
      @user = user
      @product = product
    end

    def call
      alert = Commerce::ProductAvailabilityAlert.find_by(user: @user, product: @product)
      alert&.destroy!
      ServiceResult.success
    end
  end
end
