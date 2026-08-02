# frozen_string_literal: true

module Commerce
  class AvailabilityMailer < ApplicationMailer
    def product_available(alert_id)
      @alert = Commerce::ProductAvailabilityAlert.includes(:product, :user).find(alert_id)
      @user = @alert.user
      @product = @alert.product

      mail(to: @user.email, subject: commerce_subject(:product_available, product: @product.name))
    end

    private

    def commerce_subject(name, **options)
      recipient_t("mcweb.mail.commerce.subjects.#{name}", **options)
    end
  end
end
