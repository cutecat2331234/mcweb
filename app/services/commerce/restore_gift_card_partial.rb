# frozen_string_literal: true

module Commerce
  class RestoreGiftCardPartial < ApplicationService
    def initialize(order:, refund_amount_cents:, payment_amount_cents:, already_refunded_cents: 0)
      @order = order
      @refund_amount_cents = refund_amount_cents.to_i
      @payment_amount_cents = payment_amount_cents.to_i
      @already_refunded_cents = already_refunded_cents.to_i
    end

    def call
      return ServiceResult.success(restored_cents: 0) unless @payment_amount_cents.positive?

      restored_cents = 0
      ledger_failure = nil
      Commerce::GiftCard.transaction do
        @order.lock!
        @order.reload

        original = [
          @order.gift_card_amount_cents.to_i,
          @order.gift_card_restored_cents.to_i
        ].max
        next unless original.positive?

        card = @order.gift_card
        return ServiceResult.failure(error: "gift_card_invalid") unless card

        already_restored = @order.gift_card_restored_cents.to_i
        remaining = original - already_restored
        next unless remaining.positive?

        target_restored = cumulative_target(original)
        restored_cents = [ target_restored - already_restored, remaining ].min
        next unless restored_cents.positive?

        card.lock!
        card.update!(balance_cents: card.balance_cents + restored_cents, active: true)
        ledger_result = Commerce::RecordGiftCardTransaction.call(
          gift_card: card,
          amount_cents: restored_cents,
          transaction_type: :credit,
          order: @order
        )
        unless ledger_result.success?
          ledger_failure = ledger_result
          raise ActiveRecord::Rollback
        end
        new_restored = already_restored + restored_cents
        updates = { gift_card_restored_cents: new_restored }
        updates[:gift_card_amount_cents] = 0 if new_restored >= original
        @order.update!(updates)
      end

      return ledger_failure if ledger_failure

      ServiceResult.success(restored_cents: restored_cents)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def cumulative_target(original_cents)
      Commerce::CumulativeRefundAllocation.target(
        total_units: original_cents,
        refunded_cents: @already_refunded_cents + @refund_amount_cents,
        payment_cents: @payment_amount_cents
      )
    end
  end
end
