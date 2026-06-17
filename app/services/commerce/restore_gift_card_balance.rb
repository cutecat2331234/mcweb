# frozen_string_literal: true

module Commerce
  class RestoreGiftCardBalance < ApplicationService
    def initialize(order:)
      @order = order
    end

    def call
      card = @order.gift_card
      original = @order.gift_card_amount_cents.to_i
      already_restored = @order.gift_card_restored_cents.to_i
      amount = original - already_restored
      return ServiceResult.success unless amount.positive?
      return ServiceResult.failure(error: "礼品卡信息无效。") unless card

      Commerce::GiftCard.transaction do
        card.lock!
        card.update!(
          balance_cents: card.balance_cents + amount,
          active: true
        )
        Commerce::RecordGiftCardTransaction.call(
          gift_card: card,
          amount_cents: amount,
          transaction_type: :credit,
          order: @order
        )
        @order.update!(gift_card_amount_cents: 0, gift_card_restored_cents: original)
      end

      ServiceResult.success
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
