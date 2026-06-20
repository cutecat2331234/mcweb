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
      return ServiceResult.failure(error: "Refund window has expired.") unless within_refund_window?

      refund = nil
      failure_error = nil

      Commerce::Order.transaction do
        @order.lock!
        @order.reload

        payment = succeeded_payment
        unless payment
          failure_error = "No payment found."
          raise ActiveRecord::Rollback
        end

        if Commerce::Refund.where(order: @order, status: "pending").exists?
          failure_error = "Refund already pending."
          raise ActiveRecord::Rollback
        end

        max_cents = refundable_cents(payment)
        if max_cents <= 0
          failure_error = "No refundable amount remaining."
          raise ActiveRecord::Rollback
        end

        requested = @amount_cents.present? ? @amount_cents.to_i : max_cents
        if requested <= 0
          failure_error = "refund_amount_invalid"
          raise ActiveRecord::Rollback
        end
        if requested > max_cents
          failure_error = "refund_amount_exceeds_limit"
          raise ActiveRecord::Rollback
        end

        refund = Commerce::Refund.create!(
          order: @order,
          payment_record: payment,
          status: "pending",
          amount_cents: requested,
          reason: @reason || "Customer request",
          requested_by: @user,
          requested_by_customer: true
        )
      end

      return ServiceResult.failure(error: failure_error) if failure_error.present?

      Commerce::OrderEvent.create!(
        order: @order,
        actor: @user,
        event_type: "refund_requested",
        metadata: { refund_id: refund.id, amount_cents: refund.amount_cents }
      )

      Commerce::NotifyOrderEvent.call(
        user: @order.user,
        notification_type: "commerce.refund_requested",
        title: I18n.t("mcweb.labels.notification_types.commerce.refund_requested"),
        body: I18n.t("mcweb.mail.order.refund_requested.body", number: @order.order_number),
        path: "/app/store/orders/#{@order.public_id}"
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

    def within_refund_window?
      Commerce::RefundWindow.within_window?(@order)
    end

    def succeeded_payment
      @order.primary_succeeded_payment_record
    end
  end
end
