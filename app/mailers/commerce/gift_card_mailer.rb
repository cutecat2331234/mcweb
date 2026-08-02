# frozen_string_literal: true

module Commerce
  class GiftCardMailer < ApplicationMailer
    def gift_card_created(gift_card_id, recipient_email)
      @card = Commerce::GiftCard.find(gift_card_id)
      @recipient_email = recipient_email.to_s.strip.downcase
      @user = User.find_by("LOWER(email) = ?", @recipient_email)
      mail(
        to: @recipient_email,
        subject: commerce_subject(:gift_card_created, code: @card.code)
      )
    end

    def expiry_reminder(gift_card_id, user_id)
      @card = Commerce::GiftCard.find(gift_card_id)
      @user = User.find(user_id)
      return unless NotificationPreference.enabled?(@user, channel: "email", notification_type: "commerce.gift_card_expiry")

      mail(to: @user.email, subject: commerce_subject(:gift_card_expiry, code: @card.code))
    end

    def gift_card_purchased(order_id, gift_card_ids)
      @order = Commerce::Order.find(order_id)
      @user = @order.user
      @cards = Commerce::GiftCard.where(id: gift_card_ids)
      mail(
        to: @order.user.email,
        subject: commerce_subject(:gift_card_purchased, number: @order.order_number)
      )
    end

    private

    def commerce_subject(name, **options)
      recipient_t("mcweb.mail.commerce.subjects.#{name}", **options)
    end
  end
end
