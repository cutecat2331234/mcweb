# frozen_string_literal: true

module Commerce
  class RestoreStoreCredit < ApplicationService
    def initialize(order:)
      @order = order
    end

    def call
      user = @order.user
      return ServiceResult.failure(error: "user_invalid") unless user

      Commerce::Order.transaction do
        @order.lock!
        @order.reload

        original = @order.store_credit_amount_cents.to_i
        already_restored = @order.store_credit_restored_cents.to_i
        amount = original - already_restored
        next if amount <= 0

        user.lock!
        user.update!(store_credit_cents: user.store_credit_cents.to_i + amount)
        Commerce::StoreCreditTransaction.create!(
          user: user,
          order: @order,
          amount_cents: amount,
          note: I18n.t("mcweb.commerce.notes.store_credit_order_refund", number: @order.order_number),
        )
        @order.update!(store_credit_amount_cents: 0, store_credit_restored_cents: original)
      end

      ServiceResult.success
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
