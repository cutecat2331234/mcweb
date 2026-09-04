# frozen_string_literal: true

module Commerce
  class RestoreGiftCardBalance < ApplicationService
    def initialize(order:)
      @order = order
    end

    def call
      card = @order.gift_card
      original = @order.gift_card_amount_cents.to_i
      return ServiceResult.success unless original.positive?
      return ServiceResult.failure(error: "gift_card_invalid") unless card

      ledger_failure = nil
      Commerce::GiftCard.transaction do
        @order.lock!
        @order.reload
        card.lock!

        already_restored = @order.gift_card_restored_cents.to_i
        amount = original - already_restored
        next if amount <= 0

        card.update!(
          balance_cents: card.balance_cents + amount,
          active: true
        )
        ledger_result = Commerce::RecordGiftCardTransaction.call(
          gift_card: card,
          amount_cents: amount,
          transaction_type: :credit,
          order: @order
        )
        unless ledger_result.success?
          ledger_failure = ledger_result
          raise ActiveRecord::Rollback
        end
        @order.update!(gift_card_amount_cents: 0, gift_card_restored_cents: original)
      end

      return ledger_failure if ledger_failure

      ServiceResult.success
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
