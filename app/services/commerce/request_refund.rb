# frozen_string_literal: true

module Commerce
  class RequestRefund < ApplicationService
    def initialize(order:, user:, reason: nil)
      @order = order
      @user = user
      @reason = reason
    end

    def call
      return ServiceResult.failure(error: "Not your order.") unless @order.user_id == @user.id
      return ServiceResult.failure(error: "Order is not refundable.") unless %w[paid fulfilled completed].include?(@order.status)

      payment = @order.payment_records.where(status: "succeeded").order(created_at: :desc).first
      return ServiceResult.failure(error: "No payment found.") unless payment

      existing = Commerce::Refund.where(order: @order, status: %w[pending completed]).exists?
      return ServiceResult.failure(error: "Refund already requested.") if existing

      refund = Commerce::Refund.create!(
        order: @order,
        payment_record: payment,
        status: "pending",
        amount_cents: payment.amount_cents,
        reason: @reason || "Customer request",
        requested_by: @user,
        requested_by_customer: true
      )

      Commerce::OrderEvent.create!(
        order: @order,
        actor: @user,
        event_type: "refund_requested",
        metadata: { refund_id: refund.id }
      )

      ServiceResult.success(refund)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
