# frozen_string_literal: true

module Commerce
  class PreviewGiftCard < ApplicationService
    def initialize(subtotal_cents:, code:, discount_cents: 0, shipping_cents: 0, gift_wrap_cents: 0)
      @subtotal_cents = subtotal_cents
      @code = code.to_s.strip.upcase
      @discount_cents = discount_cents
      @shipping_cents = shipping_cents.to_i
      @gift_wrap_cents = gift_wrap_cents.to_i
    end

    def call
      card = Commerce::GiftCard.find_by(code: @code)
      return ServiceResult.failure(error: "gift_card_unavailable") unless card

      reason = card.inapplicable_reason
      return ServiceResult.failure(error: "gift_card_unavailable") if reason

      payable = [ @subtotal_cents - @discount_cents + @shipping_cents + @gift_wrap_cents, 0 ].max
      amount = card.applicable_amount_cents(payable)
      return ServiceResult.failure(error: "gift_card_unavailable") unless amount.positive?

      ServiceResult.success(
        code: card.code,
        gift_card_amount_cents: amount,
        total_cents: payable - amount
      )
    end
  end
end
