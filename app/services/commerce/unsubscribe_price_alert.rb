# frozen_string_literal: true

module Commerce
  class UnsubscribePriceAlert < ApplicationService
    def initialize(user:, product:)
      @user = user
      @product = product
    end

    def call
      alert = Commerce::PriceAlert.find_by(user: @user, product: @product)
      return ServiceResult.failure(error: "未找到订阅记录。") unless alert

      alert.destroy!
      ServiceResult.success
    end
  end
end
