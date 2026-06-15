# frozen_string_literal: true

module Commerce
  class RequestRefund < ApplicationService
    def initialize(order:, user:, reason: nil, amount_cents: nil)
      @order = order
      @user = user
      @reason = reason
      @amount_cents = amount_cents
    end

    def call
      return ServiceResult.failure(error: "Not your order.") unless @order.user_id == @user.id
      return ServiceResult.failure(error: "Order is not refundable.") unless %w[paid fulfilled completed].include?(@order.status)

      payment = @order.payment_records.where(status: "succeeded").order(created_at: :desc).first
      return ServiceResult.failure(error: "No payment found.") unless payment

      return ServiceResult.failure(error: "Refund already pending.") if Commerce::Refund.where(order: @order, status: "pending").exists?

      max_cents = refundable_cents(payment)
      return ServiceResult.failure(error: "No refundable amount remaining.") if max_cents <= 0

      requested = @amount_cents.present? ? @amount_cents.to_i : max_cents
      return ServiceResult.failure(error: "退款金额无效。") if requested <= 0
      return ServiceResult.failure(error: "退款金额超过可退上限。") if requested > max_cents

      refund = Commerce::Refund.create!(
        order: @order,
        payment_record: payment,
        status: "pending",
        amount_cents: requested,
        reason: @reason || "Customer request",
        requested_by: @user,
        requested_by_customer: true
      )

      Commerce::OrderEvent.create!(
        order: @order,
        actor: @user,
        event_type: "refund_requested",
        metadata: { refund_id: refund.id, amount_cents: requested }
      )

      Commerce::NotifyOrderEvent.call(
        user: @order.user,
        notification_type: "commerce.refund_requested",
        title: "退款申请已提交",
        body: "订单 #{@order.order_number} 退款申请正在审核。",
        path: "/store/orders/#{@order.public_id}"
      )

      MailDeliveryJob.perform_later("Commerce::OrderMailer", "refund_requested", "deliver_now", args: [ refund.id ])

      ServiceResult.success(refund)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def refundable_cents(payment)
      refunded = Commerce::Refund.where(order: @order, status: %w[pending completed]).sum(:amount_cents)
      [ payment.amount_cents - refunded, 0 ].max
    end
  end
end
