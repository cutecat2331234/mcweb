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

      ServiceResult.success(@refund)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
