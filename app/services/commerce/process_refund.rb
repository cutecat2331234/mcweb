# frozen_string_literal: true

module Commerce
  class ProcessRefund < ApplicationService
    def initialize(order:, payment_record:, amount_cents:, reason: nil, requested_by: nil, approved_by: nil)
      @order = order
      @payment_record = payment_record
      @amount_cents = amount_cents
      @reason = reason
      @requested_by = requested_by
      @approved_by = approved_by
    end

    def call
      return ServiceResult.failure(error: "Payment is not refundable.") unless @payment_record.status == "succeeded"
      return ServiceResult.failure(error: "Refund amount exceeds payment amount.") if @amount_cents > @payment_record.amount_cents

      refund = nil
      Commerce::Refund.transaction do
        refund = Commerce::Refund.create!(
          order: @order,
          payment_record: @payment_record,
          status: "pending",
          amount_cents: @amount_cents,
          reason: @reason,
          requested_by: @requested_by,
          approved_by: @approved_by
        )

        provider = Payments::Provider.for(@payment_record.provider)
        result = provider.process_refund(refund)

        if result.success?
          refund.update!(status: "completed") unless refund.completed?
          if full_refund?
            @order.update!(status: "refunded")
            restore_stock!
          end
        else
          refund.update!(status: "rejected")
          return result
        end
      end

      Administration::AuditLogger.call(
        actor: @approved_by || @requested_by,
        action: "commerce.refund_processed",
        resource: refund,
        metadata: { amount_cents: @amount_cents }
      )

      ServiceResult.success(refund)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def full_refund?
      @amount_cents >= @payment_record.amount_cents
    end

    def restore_stock!
      @order.items.includes(:product, :variant).find_each do |item|
        target = item.variant || item.product
        next if target.stock.nil?

        target.update!(stock: target.stock + item.quantity)
      end
    end
  end
end
