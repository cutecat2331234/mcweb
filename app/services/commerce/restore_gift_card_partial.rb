# frozen_string_literal: true

module Commerce
  class RestoreGiftCardPartial < ApplicationService
    def initialize(order:, refund_amount_cents:, payment_amount_cents:)
      @order = order
      @refund_amount_cents = refund_amount_cents.to_i
      @payment_amount_cents = payment_amount_cents.to_i
    end

    def call
      card = @order.gift_card
      original = @order.gift_card_amount_cents.to_i
      return ServiceResult.success(restored_cents: 0) unless card && original.positive?

      already_restored = @order.gift_card_restored_cents.to_i
      remaining = original - already_restored
      return ServiceResult.success(restored_cents: 0) unless remaining.positive?
      return ServiceResult.success(restored_cents: 0) unless @payment_amount_cents.positive?

      ratio = @refund_amount_cents.to_f / @payment_amount_cents
      restore = (remaining * ratio).round
      restore = [ restore, remaining ].min
      return ServiceResult.success(restored_cents: 0) unless restore.positive?

      Commerce::GiftCard.transaction do
        card.lock!
        card.update!(balance_cents: card.balance_cents + restore, active: true)
        Commerce::RecordGiftCardTransaction.call(
          gift_card: card,
          amount_cents: restore,
          transaction_type: :credit,
          order: @order
        )
        new_restored = already_restored + restore
        updates = { gift_card_restored_cents: new_restored }
        updates[:gift_card_amount_cents] = 0 if new_restored >= original
        @order.update!(updates)
      end

      ServiceResult.success(restored_cents: restore)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
