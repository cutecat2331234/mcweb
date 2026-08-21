# frozen_string_literal: true

module Commerce
  class RejectRefund < ApplicationService
    def initialize(refund:, actor:, reason: nil, reason_kind: nil)
      @refund = refund
      @actor = actor
      @reason = reason
      @reason_kind = reason_kind.to_s.presence
    end

    def call
      rejection_error = nil

      Commerce::Refund.transaction do
        order, _payment, refund = Commerce::FinancialLocking.lock_order_payment_refund!(
          order_id: @refund.store_order_id,
          payment_record_id: @refund.payment_record_id,
          refund_id: @refund.id
        )
        unless refund.pending?
          rejection_error = :refund_not_pending
          raise ActiveRecord::Rollback
        end

        refund.update!(
          status: "rejected",
          approved_by: @actor,
          reason: resolved_reason(refund),
          reason_kind: resolved_reason_kind(refund)
        )
        Commerce::OrderEvent.create!(
          order: order,
          actor: @actor,
          event_type: "refund_rejected",
          metadata: { refund_id: refund.id, reason: @reason }
        )
        Commerce::DomainEvents.publish_after_commit(
          "commerce.refund.rejected",
          Commerce::DomainEvents.refund(refund)
        )
        @refund = refund
      end

      return ServiceResult.failure(error: rejection_error, code: rejection_error) if rejection_error.present?

      MailDeliveryJob.perform_later("Commerce::OrderMailer", "refund_rejected", "deliver_now", args: [ @refund.id ])

      Commerce::NotifyOrderEvent.call(
        user: @refund.order.user,
        notification_type: "commerce.refund_rejected",
        title: -> { I18n.t("mcweb.labels.notification_types.commerce.refund_rejected") },
        body: -> { I18n.t("mcweb.mail.commerce.refund_rejected.body", number: @refund.order.order_number) },
        path: "/app/store/orders/#{@refund.order.public_id}"
      )

      ServiceResult.success(@refund)
    rescue Commerce::FinancialLocking::BindingMismatch
      ServiceResult.failure(error: :refund_binding_mismatch, code: :refund_binding_mismatch)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def resolved_reason(refund)
      return @reason if @reason.present?
      return nil if @reason_kind.present?

      refund.reason
    end

    def resolved_reason_kind(refund)
      return @reason_kind if @reason_kind.present?
      return nil if @reason.present?

      refund.reason_kind
    end
  end
end
