# frozen_string_literal: true

module Commerce
  class ConfirmPayment < ApplicationService
    def initialize(payment_record:, provider_payment_id: nil, metadata: {})
      @payment_record = payment_record
      @provider_payment_id = provider_payment_id
      @metadata = metadata
    end

    def call
      newly_paid = false
      order_id = nil

      Payments::Record.transaction do
        record = Payments::Record.lock.find(@payment_record.id)

        if record.status == "succeeded"
          return ServiceResult.success(record: record, idempotent: true, newly_paid: false)
        end

        record.update!(
          status: "succeeded",
          provider_payment_id: @provider_payment_id || record.provider_payment_id,
          metadata: record.metadata.merge(@metadata)
        )

        order = record.order
        order_id = order.id

        if %w[pending awaiting_payment].include?(order.status)
          from_status = order.status
          order.submit_payment! if order.pending? && order.may_submit_payment?
          order.mark_paid! if order.awaiting_payment? && order.may_mark_paid?
          order.update!(status: "paid") if order.status != "paid"

          Commerce::OrderEvent.create!(
            order: order,
            event_type: "payment_confirmed",
            from_status: from_status,
            to_status: "paid",
            metadata: { payment_record_id: record.id }
          )
          newly_paid = true
        end
      end

      Commerce::FulfillOrderJob.perform_later(order_id) if newly_paid && order_id
      if newly_paid && order_id
        order = Commerce::Order.find(order_id)
        MailDeliveryJob.perform_later("Commerce::OrderMailer", "payment_confirmed", "deliver_now", args: [ order_id ])
        Commerce::NotifyOrderEvent.call(
          user: order.user,
          notification_type: "commerce.payment_confirmed",
          title: "支付成功",
          body: "订单 #{order.order_number} 已支付成功。",
          path: "/store/orders/#{order.public_id}"
        )
        Community::CheckAutoBadges.call(user: order.user)
      end

      ServiceResult.success(record: @payment_record.reload, idempotent: false, newly_paid: newly_paid)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
