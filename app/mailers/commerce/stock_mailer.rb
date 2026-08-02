# frozen_string_literal: true

module Commerce
  class StockMailer < ApplicationMailer
    def restocked(alert_id)
      @alert = Commerce::StockAlert.includes(:product, :variant, :user).find(alert_id)
      @user = @alert.user
      @product = @alert.product

      mail(to: @user.email, subject: commerce_subject(:stock_restocked, product: @product.name))
    end

    private

    def commerce_subject(name, **options)
      recipient_t("mcweb.mail.commerce.subjects.#{name}", **options)
    end
  end
end
