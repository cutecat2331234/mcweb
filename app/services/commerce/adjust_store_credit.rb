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
      return ServiceResult.failure(error: "store_credit_unauthorized") unless authorized?
      return ServiceResult.failure(error: "store_credit_adjustment_zero") if @amount_cents.zero?

      new_balance = nil

      Commerce::StoreCreditTransaction.transaction do
        @user.lock!
        new_balance = @user.store_credit_cents.to_i + @amount_cents
        return ServiceResult.failure(error: "store_credit_negative_balance") if new_balance.negative?

        reserved = @user.store_credit_cents.to_i - @user.available_store_credit_cents
        if new_balance < reserved
          return ServiceResult.failure(error: "store_credit_below_reserved")
        end

        @user.update!(store_credit_cents: new_balance)
        Commerce::StoreCreditTransaction.create!(
          user: @user,
          actor: @actor,
          amount_cents: @amount_cents,
          note: @note || I18n.t("mcweb.commerce.notes.admin_store_credit_adjustment"),
        )
      end

      ServiceResult.success(balance_cents: new_balance)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def authorized?
      return false if @actor.id == @user.id

      @actor.permission?("store.orders.read") || @actor.permission?("admin.access")
    end
  end
end
