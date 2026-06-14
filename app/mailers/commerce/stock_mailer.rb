# frozen_string_literal: true

module Commerce
  class StockMailer < ApplicationMailer
    def restocked(alert_id)
      @alert = Commerce::StockAlert.includes(:product, :variant, :user).find(alert_id)
      @user = @alert.user
      @product = @alert.product

      mail(to: @user.email, subject: "商品到货通知：#{@product.name}")
    end
  end
end
