# frozen_string_literal: true

module Commerce
  class DebitGiftCard < ApplicationService
    def initialize(order:)
      @order = order
    end

    def call
      amount = @order.gift_card_amount_cents.to_i
      return ServiceResult.success unless amount.positive?

      card = @order.gift_card
      return ServiceResult.failure(error: "gift_card_invalid") unless card

      Commerce::GiftCard.transaction do
        card.lock!
        return ServiceResult.success if card.transactions.exists?(order: @order, transaction_type: :debit)

        reason = card.inapplicable_reason
        return ServiceResult.failure(error: "gift_card_unavailable") if reason

        available = card.available_balance_cents(excluding_order: @order)
        return ServiceResult.failure(error: "gift_card_unavailable") if amount > available

        card.update!(
          balance_cents: card.balance_cents - amount,
          active: (card.balance_cents - amount).positive?
        )
        Commerce::RecordGiftCardTransaction.call(
          gift_card: card,
          amount_cents: -amount,
          transaction_type: :debit,
          order: @order
        )
      end

      ServiceResult.success
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
