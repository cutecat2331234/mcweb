# frozen_string_literal: true

module Commerce
  class PreviewGiftCard < ApplicationService
    def initialize(subtotal_cents:, code:, discount_cents: 0, shipping_cents: 0)
      @subtotal_cents = subtotal_cents
      @code = code.to_s.strip.upcase
      @discount_cents = discount_cents
      @shipping_cents = shipping_cents.to_i
    end

    def call
      card = Commerce::GiftCard.find_by(code: @code)
      return ServiceResult.failure(error: "礼品卡代码无效。") unless card

      reason = card.inapplicable_reason
      return ServiceResult.failure(error: reason) if reason

      payable = [ @subtotal_cents - @discount_cents + @shipping_cents, 0 ].max
      amount = card.applicable_amount_cents(payable)
      return ServiceResult.failure(error: "礼品卡余额不足。") unless amount.positive?

      ServiceResult.success(
        code: card.code,
        gift_card_amount_cents: amount,
        total_cents: payable - amount
      )
    end
  end
end
