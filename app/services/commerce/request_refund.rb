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
      return refund_failure(:not_your_order) unless @order.user_id == @user.id
      return refund_failure(:order_is_not_refundable) unless %w[paid fulfilled completed].include?(@order.status)
      return refund_failure(:refund_window_has_expired) unless within_refund_window?

      refund = nil
      failure_error = nil

      Commerce::Order.transaction do
        @order = Commerce::Order.lock.find(@order.id)

        payment = succeeded_payment
        unless payment
          failure_error = :refund_payment_not_found
          raise ActiveRecord::Rollback
        end
        @order, payment = Commerce::FinancialLocking.lock_order_payment!(
          order_id: @order.id,
          payment_record_id: payment.id
        )

        if Commerce::Disputes::CustomerPolicy.active_financial_dispute?(payment)
          failure_error = :refund_blocked_by_active_dispute
          raise ActiveRecord::Rollback
        end

        if @order.refunds.provider_unknown.exists?
          failure_error = :refund_reconciliation_required
          raise ActiveRecord::Rollback
        end

        if Commerce::Refund.where(order: @order).in_flight.exists?
          failure_error = :refund_already_pending
          raise ActiveRecord::Rollback
        end

        max_cents = refundable_cents(payment)
        if max_cents <= 0
          failure_error = :refund_no_balance
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
          reason: @reason.presence,
          reason_kind: "customer_request",
          requested_by: @user,
          requested_by_customer: true
        )
        Commerce::OrderEvent.create!(
          order: @order,
          actor: @user,
          event_type: "refund_requested",
          metadata: { refund_id: refund.id, amount_cents: refund.amount_cents }
        )
        Commerce::DomainEvents.publish_after_commit(
          "commerce.refund.requested",
          Commerce::DomainEvents.refund(refund)
        )
      end

      return refund_failure(failure_error) if failure_error.present?

      Commerce::NotifyOrderEvent.call(
        user: @order.user,
        notification_type: "commerce.refund_requested",
        title: -> { I18n.t("mcweb.labels.notification_types.commerce.refund_requested") },
        body: -> { I18n.t("mcweb.mail.commerce.refund_requested.body", number: @order.order_number) },
        path: "/app/store/orders/#{@order.public_id}"
      )

      refund_id = refund.id
      ActiveRecord.after_all_transactions_commit do
        MailDeliveryJob.perform_later(
          "Commerce::OrderMailer",
          "refund_requested",
          "deliver_now",
          args: [ refund_id ]
        )
      end

      ServiceResult.success(refund)
    rescue Commerce::FinancialLocking::BindingMismatch
      refund_failure(:refund_binding_mismatch)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def refund_failure(code)
      ServiceResult.failure(error: code, code: code)
    end

    def refundable_cents(payment)
      refunded = payment.refunds.reserved.sum(:amount_cents)
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
