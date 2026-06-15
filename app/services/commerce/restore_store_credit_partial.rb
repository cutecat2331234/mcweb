# frozen_string_literal: true

module Commerce
  class RestoreStoreCreditPartial < ApplicationService
    def initialize(order:, refund_amount_cents:, payment_amount_cents:)
      @order = order
      @refund_amount_cents = refund_amount_cents.to_i
      @payment_amount_cents = payment_amount_cents.to_i
    end

    def call
      original_credit = @order.store_credit_amount_cents.to_i
      return ServiceResult.success(restored_cents: 0) unless original_credit.positive?

      already_restored = @order.store_credit_restored_cents.to_i
      remaining = original_credit - already_restored
      return ServiceResult.success(restored_cents: 0) unless remaining.positive?
      return ServiceResult.success(restored_cents: 0) unless @payment_amount_cents.positive?

      ratio = @refund_amount_cents.to_f / @payment_amount_cents
      restore = (remaining * ratio).round
      restore = [ restore, remaining ].min
      return ServiceResult.success(restored_cents: 0) unless restore.positive?

      user = @order.user
      Commerce::Order.transaction do
        user.lock!
        user.update!(store_credit_cents: user.store_credit_cents.to_i + restore)
        Commerce::StoreCreditTransaction.create!(
          user: user,
          order: @order,
          amount_cents: restore,
          note: "订单 #{@order.order_number} 退款退还余额"
        )
        new_restored = already_restored + restore
        updates = { store_credit_restored_cents: new_restored }
        updates[:store_credit_amount_cents] = 0 if new_restored >= original_credit
        @order.update!(updates)
      end

      ServiceResult.success(restored_cents: restore)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
