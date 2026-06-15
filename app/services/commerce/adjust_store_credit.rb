# frozen_string_literal: true

module Commerce
  class AdjustStoreCredit < ApplicationService
    def initialize(actor:, user:, amount_cents:, note: nil)
      @actor = actor
      @user = user
      @amount_cents = amount_cents.to_i
      @note = note.to_s.strip.presence
    end

    def call
      return ServiceResult.failure(error: "无权调整商店余额。") unless authorized?
      return ServiceResult.failure(error: "调整金额不能为零。") if @amount_cents.zero?

      new_balance = @user.store_credit_cents.to_i + @amount_cents
      return ServiceResult.failure(error: "余额不能为负数。") if new_balance.negative?

      Commerce::StoreCreditTransaction.transaction do
        @user.update!(store_credit_cents: new_balance)
        Commerce::StoreCreditTransaction.create!(
          user: @user,
          actor: @actor,
          amount_cents: @amount_cents,
          note: @note || "管理员调整"
        )
      end

      ServiceResult.success(balance_cents: new_balance)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def authorized?
      @actor.permission?("store.orders.read") || @actor.permission?("admin.access")
    end
  end
end
