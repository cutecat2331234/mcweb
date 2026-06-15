# frozen_string_literal: true

module Commerce
  class PreviewStoreCredit < ApplicationService
    def initialize(user:, subtotal_cents:, discount_cents: 0, shipping_cents: 0, gift_wrap_cents: 0, gift_card_amount_cents: 0)
      @user = user
      @subtotal_cents = subtotal_cents.to_i
      @discount_cents = discount_cents.to_i
      @shipping_cents = shipping_cents.to_i
      @gift_wrap_cents = gift_wrap_cents.to_i
      @gift_card_amount_cents = gift_card_amount_cents.to_i
    end

    def call
      balance = @user.store_credit_cents.to_i
      payable = [ @subtotal_cents - @discount_cents + @shipping_cents + @gift_wrap_cents - @gift_card_amount_cents, 0 ].max
      amount = [ payable, balance ].min

      ServiceResult.success(
        balance_cents: balance,
        store_credit_amount_cents: amount,
        total_cents: payable - amount
      )
    end
  end
end
