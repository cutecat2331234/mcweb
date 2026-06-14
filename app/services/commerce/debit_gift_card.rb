# frozen_string_literal: true

module Commerce
  class DebitGiftCard < ApplicationService
    def initialize(order:)
      @order = order
    end

    def call
      card = @order.gift_card
      amount = @order.gift_card_amount_cents.to_i
      return ServiceResult.success unless card && amount.positive?

      Commerce::GiftCard.transaction do
        card.lock!
        debit = [ amount, card.balance_cents ].min
        card.update!(
          balance_cents: card.balance_cents - debit,
          active: (card.balance_cents - debit).positive?
        )
        Commerce::RecordGiftCardTransaction.call(
          gift_card: card,
          amount_cents: -debit,
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
