# frozen_string_literal: true

module Commerce
  class RecordGiftCardTransaction < ApplicationService
    def initialize(gift_card:, amount_cents:, transaction_type:, order: nil)
      @gift_card = gift_card
      @amount_cents = amount_cents
      @transaction_type = transaction_type.to_s
      @order = order
    end

    def call
      Commerce::GiftCardTransaction.create!(
        gift_card: @gift_card,
        amount_cents: @amount_cents,
        transaction_type: @transaction_type,
        order: @order,
        balance_after_cents: @gift_card.balance_cents,
        created_at: Time.current
      )
      ServiceResult.success
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
