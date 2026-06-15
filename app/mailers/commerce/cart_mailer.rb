# frozen_string_literal: true

module Commerce
  class CartMailer < ApplicationMailer
    def abandoned_cart(cart_id, second = false)
      @cart = Commerce::Cart.includes(items: :product).find(cart_id)
      @user = @cart.user
      return unless @user
      return unless NotificationPreference.enabled?(@user, channel: "email", notification_type: "commerce.abandoned_cart")

      @cart.ensure_recovery_token!
      @recovery_url = @cart.recovery_cart_url
      @second_reminder = ActiveModel::Type::Boolean.new.cast(second)

      subject = @second_reminder ? "您的购物车仍在等待结账" : "您的购物车还有未结算商品"
      mail(to: @user.email, subject: subject)
    end
  end
end
