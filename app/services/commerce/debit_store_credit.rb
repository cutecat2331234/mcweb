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
      return ServiceResult.failure(error: "user_invalid") unless user

      Commerce::Order.transaction do
        user.lock!
        return ServiceResult.success if Commerce::StoreCreditTransaction.where(order: @order).where("amount_cents < 0").exists?

        balance = user.store_credit_cents.to_i
        return ServiceResult.failure(error: "store_credit_insufficient") if balance < amount

        new_balance = balance - amount
        user.update!(store_credit_cents: new_balance)
        Commerce::StoreCreditTransaction.create!(
          user: user,
          order: @order,
          amount_cents: -amount,
          balance_before_cents: balance,
          balance_after_cents: new_balance,
          note: I18n.t("mcweb.commerce.notes.store_credit_order_debit", number: @order.order_number),
        )
      end

      ServiceResult.success
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
