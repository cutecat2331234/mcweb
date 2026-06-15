# frozen_string_literal: true

module Commerce
  class RestoreStoreCredit < ApplicationService
    def initialize(order:)
      @order = order
    end

    def call
      amount = @order.store_credit_amount_cents.to_i
      return ServiceResult.success unless amount.positive?

      user = @order.user
      Commerce::Order.transaction do
        user.lock!
        user.update!(store_credit_cents: user.store_credit_cents.to_i + amount)
        Commerce::StoreCreditTransaction.create!(
          user: user,
          order: @order,
          amount_cents: amount,
          note: "订单 #{@order.order_number} 退还余额"
        )
        @order.update!(store_credit_amount_cents: 0)
      end

      ServiceResult.success
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
