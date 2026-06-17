# frozen_string_literal: true

module Commerce
  class RejectRefund < ApplicationService
    def initialize(refund:, actor:, reason: nil)
      @refund = refund
      @actor = actor
      @reason = reason
    end

    def call
      return ServiceResult.failure(error: "Refund is not pending.") unless @refund.pending?

      @refund.update!(status: "rejected", approved_by: @actor, reason: @reason.presence || @refund.reason)

      Commerce::OrderEvent.create!(
        order: @refund.order,
        actor: @actor,
        event_type: "refund_rejected",
        metadata: { refund_id: @refund.id, reason: @reason }
      )

      MailDeliveryJob.perform_later("Commerce::OrderMailer", "refund_rejected", "deliver_now", args: [ @refund.id ])

      Commerce::NotifyOrderEvent.call(
        user: @refund.order.user,
        notification_type: "commerce.refund_rejected",
        title: "退款申请被拒绝",
        body: "订单 #{@refund.order.order_number} 的退款申请未通过审核。",
        path: "/app/store/orders/#{@refund.order.public_id}"
      )

      ServiceResult.success(@refund)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
