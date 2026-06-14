# frozen_string_literal: true

module Commerce
  class ProcessRefund < ApplicationService
    def initialize(order:, payment_record:, amount_cents:, reason: nil, requested_by: nil, approved_by: nil, existing_refund: nil)
      @order = order
      @payment_record = payment_record
      @amount_cents = amount_cents
      @reason = reason
      @requested_by = requested_by
      @approved_by = approved_by
      @existing_refund = existing_refund
    end

    def call
      return ServiceResult.failure(error: "Payment is not refundable.") unless @payment_record.status == "succeeded"

      refunded_cents = @order.refunds.where(status: %w[pending completed]).where.not(id: @existing_refund&.id).sum(:amount_cents)
      remaining = @payment_record.amount_cents - refunded_cents
      return ServiceResult.failure(error: "Refund amount exceeds remaining balance.") if @amount_cents > remaining

      refund = nil
      Commerce::Refund.transaction do
        refund = find_or_build_refund
        refund.assign_attributes(
          amount_cents: @amount_cents,
          reason: @reason.presence || refund.reason,
          approved_by: @approved_by || refund.approved_by
        )
        refund.save!

        provider = Payments::Provider.for(@payment_record.provider)
        result = provider.process_refund(refund)

        if result.success?
          refund.update!(status: "completed") unless refund.completed?
          Commerce::OrderEvent.create!(
            order: @order,
            actor: @approved_by || @requested_by,
            event_type: "refund_processed",
            metadata: { refund_id: refund.id, amount_cents: @amount_cents }
          )
          if full_refund?(@amount_cents, refunded_cents)
            @order.update!(status: "refunded")
            restore_stock!
            restore_coupon_usage!
          end
          MailDeliveryJob.perform_later("Commerce::OrderMailer", "refund_processed", "deliver_now", args: [ refund.id ])
        else
          refund.update!(status: "rejected")
          Commerce::OrderEvent.create!(
            order: @order,
            actor: @approved_by,
            event_type: "refund_rejected",
            metadata: { refund_id: refund.id, reason: result.error }
          )
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

    def find_or_build_refund
      return @existing_refund if @existing_refund

      pending = @order.refunds.pending.order(created_at: :asc).first
      return pending if pending && @approved_by

      Commerce::Refund.new(
        order: @order,
        payment_record: @payment_record,
        status: "pending",
        requested_by: @requested_by
      )
    end

    def full_refund?(amount_cents, already_refunded_cents)
      amount_cents + already_refunded_cents >= @payment_record.amount_cents
    end

    def restore_stock!
      @order.items.includes(:product, :variant).find_each do |item|
        target = item.variant || item.product
        next if target.stock.nil?

        target.update!(stock: target.stock + item.quantity)
      end
    end

    def restore_coupon_usage!
      coupon = @order.coupon
      return unless coupon
      return unless coupon.used_count.positive?

      coupon.decrement!(:used_count)
    end
  end
end
