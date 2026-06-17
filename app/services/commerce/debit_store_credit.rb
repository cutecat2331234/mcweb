# frozen_string_literal: true

module Commerce
  class DebitStoreCredit < ApplicationService
    def initialize(order:)
      @order = order
    end

    def call
      amount = @order.store_credit_amount_cents.to_i
      return ServiceResult.success unless amount.positive?

      user = @order.user
      return ServiceResult.failure(error: "用户信息无效。") unless user
      return ServiceResult.success if Commerce::StoreCreditTransaction.where(order: @order).where("amount_cents < 0").exists?
      Commerce::Order.transaction do
        user.lock!
        balance = user.store_credit_cents.to_i
        return ServiceResult.failure(error: "商店余额不足。") if balance < amount

        user.update!(store_credit_cents: balance - amount)
        Commerce::StoreCreditTransaction.create!(
          user: user,
          order: @order,
          amount_cents: -amount,
          note: "订单 #{@order.order_number} 抵扣"
        )
      end

      ServiceResult.success
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
