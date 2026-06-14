# frozen_string_literal: true

module Commerce
  class UnsubscribeStockAlert < ApplicationService
    def initialize(user:, product:, variant: nil)
      @user = user
      @product = product
      @variant = variant
    end

    def call
      alert = Commerce::StockAlert.find_by(
        user: @user,
        product: @product,
        store_product_variant_id: @variant&.id
      )
      return ServiceResult.failure(error: "未找到订阅记录。") unless alert

      alert.destroy!
      ServiceResult.success
    end
  end
end
