# frozen_string_literal: true

module Commerce
  class CartMailer < ApplicationMailer
    def abandoned_cart(cart_id)
      @cart = Commerce::Cart.includes(items: :product).find(cart_id)
      @user = @cart.user
      return unless @user
      return unless NotificationPreference.enabled?(@user, channel: "email", notification_type: "commerce.abandoned_cart")

      mail(to: @user.email, subject: "您的购物车还有未结算商品")
    end
  end
end
