# frozen_string_literal: true

module Commerce
  class AvailabilityMailer < ApplicationMailer
    def product_available(alert_id)
      @alert = Commerce::ProductAvailabilityAlert.includes(:product, :user).find(alert_id)
      @user = @alert.user
      @product = @alert.product

      mail(to: @user.email, subject: "商品已上架：#{@product.name}")
    end
  end
end
