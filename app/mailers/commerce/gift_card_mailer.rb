# frozen_string_literal: true

module Commerce
  class GiftCardMailer < ApplicationMailer
    def gift_card_created(gift_card_id, recipient_email)
      @card = Commerce::GiftCard.find(gift_card_id)
      @recipient_email = recipient_email
      mail(to: recipient_email, subject: "您收到一张礼品卡：#{@card.code}")
    end

    def expiry_reminder(gift_card_id, user_id)
      @card = Commerce::GiftCard.find(gift_card_id)
      @user = User.find(user_id)
      return unless NotificationPreference.enabled?(@user, channel: "email", notification_type: "commerce.gift_card_expiry")

      mail(to: @user.email, subject: "礼品卡 #{@card.code} 即将到期")
    end

    def gift_card_purchased(order_id, gift_card_ids)
      @order = Commerce::Order.find(order_id)
      @cards = Commerce::GiftCard.where(id: gift_card_ids)
      mail(to: @order.user.email, subject: "您的礼品卡已发放 — 订单 #{@order.order_number}")
    end
  end
end
