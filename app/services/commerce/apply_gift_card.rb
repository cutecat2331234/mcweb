# frozen_string_literal: true

module Commerce
  class ApplyGiftCard < ApplicationService
    def initialize(order:, code:)
      @order = order
      @code = code.to_s.strip.upcase
    end

    def call
      return ServiceResult.failure(error: "订单无法修改。") unless @order.status == "pending"

      card = Commerce::GiftCard.find_by(code: @code)
      return ServiceResult.failure(error: "礼品卡代码无效。") unless card

      reason = card.inapplicable_reason
      return ServiceResult.failure(error: reason) if reason

      payable = [ @order.subtotal_cents - @order.discount_cents + @order.shipping_cents.to_i + @order.gift_wrap_cents.to_i, 0 ].max
      amount = 0

      Commerce::Order.transaction do
        card.lock!
        available = card.available_balance_cents(excluding_order: @order)
        return ServiceResult.failure(error: "礼品卡余额不足。") unless available.positive?

        amount = card.applicable_amount_cents(payable, excluding_order: @order)
        return ServiceResult.failure(error: "礼品卡余额不足。") unless amount.positive?

        total_cents = payable - amount

        @order.update!(
          gift_card: card,
          gift_card_amount_cents: amount,
          total_cents: total_cents
        )
      end

      ServiceResult.success(order: @order, gift_card_amount_cents: amount)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
