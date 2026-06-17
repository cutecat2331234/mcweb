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
      payment_error = nil
      from_status = nil

      Payments::Record.transaction do
        record = Payments::Record.lock.find(@payment_record.id)

        if record.status == "succeeded"
          return ServiceResult.success(record: record, idempotent: true, newly_paid: false)
        end

        unless %w[pending processing].include?(record.status)
          payment_error = "Payment is no longer valid."
          raise ActiveRecord::Rollback
        end

        order = Commerce::Order.lock.find(record.store_order_id)
        order_id = order.id

        unless order.payable?
          payment_error = order.payment_expired? ? "订单支付已过期。" : "Order is not payable."
          raise ActiveRecord::Rollback
        end

        if order.gift_card_amount_cents.to_i.positive?
          debit_result = Commerce::DebitGiftCard.call(order: order)
          unless debit_result.success?
            payment_error = debit_result.error || "礼品卡扣款失败。"
            raise ActiveRecord::Rollback
          end
        end

        if order.store_credit_amount_cents.to_i.positive?
          credit_result = Commerce::DebitStoreCredit.call(order: order)
          unless credit_result.success?
            payment_error = credit_result.error || "商店余额扣款失败。"
            raise ActiveRecord::Rollback
          end
        end

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

        record.update!(
          status: "succeeded",
          provider_payment_id: @provider_payment_id || record.provider_payment_id,
          metadata: record.metadata.merge(@metadata)
        )
      end

      return ServiceResult.failure(error: payment_error) if payment_error.present?

      if newly_paid && order_id
        order = Commerce::Order.find(order_id)
        completion = Commerce::CompleteOrderPayment.call(order: order, from_status: from_status)
        return completion unless completion.success?
      end

      ServiceResult.success(record: @payment_record.reload, idempotent: false, newly_paid: newly_paid)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
