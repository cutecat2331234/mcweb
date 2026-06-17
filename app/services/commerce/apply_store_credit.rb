# frozen_string_literal: true

module Commerce
  class ApplyStoreCredit < ApplicationService
    def initialize(order:, user:)
      @order = order
      @user = user
    end

    def call
      return ServiceResult.failure(error: "订单无法修改。") unless @order.status == "pending"
      return ServiceResult.success(order: @order, store_credit_amount_cents: 0) if @user.store_credit_cents.to_i <= 0

      payable = [ @order.subtotal_cents - @order.discount_cents + @order.shipping_cents.to_i + @order.gift_wrap_cents.to_i - @order.gift_card_amount_cents.to_i, 0 ].max
      return ServiceResult.success(order: @order, store_credit_amount_cents: 0) unless payable.positive?

      amount = [ payable, @user.store_credit_cents.to_i ].min
      return ServiceResult.success(order: @order, store_credit_amount_cents: 0) unless amount.positive?

      total_cents = payable - amount

      Commerce::Order.transaction do
        @order.update!(
          store_credit_amount_cents: amount,
          total_cents: total_cents
        )
      end

      ServiceResult.success(order: @order, store_credit_amount_cents: amount)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
