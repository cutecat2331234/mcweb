# frozen_string_literal: true

module Commerce
  class RejectRefund < ApplicationService
    def initialize(refund:, actor:, reason: nil)
      @refund = refund
      @actor = actor
      @reason = reason
    end

    def call
      rejection_error = nil

      Commerce::Refund.transaction do
        refund = Commerce::Refund.lock.find(@refund.id)
        unless refund.pending?
          rejection_error = :refund_not_pending
          raise ActiveRecord::Rollback
        end

        refund.update!(
          status: "rejected",
          approved_by: @actor,
          reason: @reason.presence || refund.reason
        )
        Commerce::OrderEvent.create!(
          order: refund.order,
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
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
