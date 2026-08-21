# frozen_string_literal: true

module Commerce
  class WithdrawRefund < ApplicationService
    def initialize(order:, refund:, user:)
      @order = order
      @refund = refund
      @user = user
    end

    def call
      return refund_failure(:refund_withdrawal_unauthorized) unless @order.user_id == @user.id

      withdrawn_refund = nil
      failure_error = nil
      idempotent = false

      Commerce::Order.transaction do
        order = Commerce::Order.lock.find(@order.id)
        payment = Payments::Record.lock.find(@refund.payment_record_id)
        refund = Commerce::Refund.lock.find(@refund.id)

        unless refund.store_order_id == order.id && payment.store_order_id == order.id && refund.payment_record_id == payment.id
          failure_error = :refund_binding_mismatch
          raise ActiveRecord::Rollback
        end
        unless order.user_id == @user.id && refund.requested_by_customer?
          failure_error = :refund_withdrawal_unauthorized
          raise ActiveRecord::Rollback
        end

        if refund.withdrawn?
          idempotent = refund.withdrawn_by_id == @user.id
          failure_error = :refund_withdrawal_no_longer_available unless idempotent
          withdrawn_refund = refund
          next
        end

        unless refund.pending? && refund.processing_started_at.nil? &&
            refund.provider_refund_id.blank? && refund.provider_confirmed_at.nil?
          failure_error = :refund_withdrawal_no_longer_available
          raise ActiveRecord::Rollback
        end

        refund.update!(status: :withdrawn, withdrawn_at: Time.current, withdrawn_by: @user)
        Commerce::OrderEvent.create!(
          order: order,
          actor: @user,
          event_type: "refund_withdrawn",
          metadata: { refund_id: refund.id, amount_cents: refund.amount_cents }
        )
        Administration::AuditLogger.call(
          actor: @user,
          action: "commerce.refund_withdrawn",
          resource: refund,
          metadata: { order_public_id: order.public_id, amount_cents: refund.amount_cents },
          before_state: { status: "pending" },
          after_state: { status: "withdrawn", withdrawn_at: refund.withdrawn_at }
        )
        Commerce::DomainEvents.publish_after_commit(
          "commerce.refund.withdrawn",
          Commerce::DomainEvents.refund(refund)
        )
        withdrawn_refund = refund
      end

      return refund_failure(failure_error) if failure_error

      ServiceResult.success(refund: withdrawn_refund, idempotent: idempotent)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def refund_failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
