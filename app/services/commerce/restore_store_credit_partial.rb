# frozen_string_literal: true

module Commerce
  class RestoreStoreCreditPartial < ApplicationService
    def initialize(order:, refund_amount_cents:, payment_amount_cents:, already_refunded_cents: 0)
      @order = order
      @refund_amount_cents = refund_amount_cents.to_i
      @payment_amount_cents = payment_amount_cents.to_i
      @already_refunded_cents = already_refunded_cents.to_i
    end

    def call
      return ServiceResult.success(restored_cents: 0) unless @payment_amount_cents.positive?

      user = @order.user
      return ServiceResult.failure(error: "user_invalid") unless user

      restored_cents = 0
      Commerce::Order.transaction do
        @order.lock!
        @order.reload

        original_credit = @order.store_credit_amount_cents.to_i
        next unless original_credit.positive?

        already_restored = @order.store_credit_restored_cents.to_i
        remaining = original_credit - already_restored
        next unless remaining.positive?

        target_restored = cumulative_target(original_credit)
        restored_cents = [ target_restored - already_restored, remaining ].min
        next unless restored_cents.positive?

        user.lock!
        user.update!(store_credit_cents: user.store_credit_cents.to_i + restored_cents)
        Commerce::StoreCreditTransaction.create!(
          user: user,
          order: @order,
          amount_cents: restored_cents,
          note: I18n.t("mcweb.commerce.notes.store_credit_order_refund", number: @order.order_number),
        )
        new_restored = already_restored + restored_cents
        updates = { store_credit_restored_cents: new_restored }
        updates[:store_credit_amount_cents] = 0 if new_restored >= original_credit
        @order.update!(updates)
      end

      ServiceResult.success(restored_cents: restored_cents)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def cumulative_target(original_cents)
      total_refunded = [ @already_refunded_cents + @refund_amount_cents, @payment_amount_cents ].min
      (original_cents * total_refunded.to_f / @payment_amount_cents).round
    end
  end
end
