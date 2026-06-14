# frozen_string_literal: true

module Commerce
  class RestoreGiftCardBalance < ApplicationService
    def initialize(order:)
      @order = order
    end

    def call
      card = @order.gift_card
      amount = @order.gift_card_amount_cents.to_i
      return ServiceResult.success unless card && amount.positive?

      Commerce::GiftCard.transaction do
        card.lock!
        card.update!(
          balance_cents: card.balance_cents + amount,
          active: true
        )
      end

      ServiceResult.success
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
