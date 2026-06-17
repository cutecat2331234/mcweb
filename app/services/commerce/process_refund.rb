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

      refund = nil
      previous_status = @order.status
      Commerce::Refund.transaction do
        @order.lock!
        @payment_record.lock!

        refunded_cents = @order.refunds.where(status: %w[pending completed]).where.not(id: @existing_refund&.id).sum(:amount_cents)
        remaining = @payment_record.amount_cents - refunded_cents
        if @amount_cents > remaining
          return ServiceResult.failure(error: "Refund amount exceeds remaining balance.")
        end

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
          Commerce::RestoreStoreCreditPartial.call(
            order: @order,
            refund_amount_cents: @amount_cents,
            payment_amount_cents: @payment_record.amount_cents
          )
          Commerce::RestoreStockPartial.call(
            order: @order,
            refund_amount_cents: @amount_cents,
            payment_amount_cents: @payment_record.amount_cents
          )
          Commerce::RestoreCouponPartial.call(
            order: @order,
            refund_amount_cents: @amount_cents,
            payment_amount_cents: @payment_record.amount_cents,
            already_refunded_cents: refunded_cents
          )
          Commerce::RestoreGiftCardPartial.call(
            order: @order,
            refund_amount_cents: @amount_cents,
            payment_amount_cents: @payment_record.amount_cents
          )
          if full_refund?(@amount_cents, refunded_cents)
            @order.update!(status: "refunded")
            restore_stock!
            restore_coupon_usage!
            restore_gift_card_balance!
            Commerce::RestoreStoreCredit.call(order: @order)
            Commerce::RevokeIssuedGiftCards.call(order: @order)
          end
          MailDeliveryJob.perform_later("Commerce::OrderMailer", "refund_processed", "deliver_now", args: [ refund.id ])
          Commerce::NotifyOrderEvent.call(
            user: @order.user,
            notification_type: "commerce.refund_processed",
            title: "退款已完成",
            body: "订单 #{@order.order_number} 退款 #{format_refund_amount(@amount_cents)} 已处理。",
            path: "/store/orders/#{@order.public_id}"
          )
          Commerce::DispatchOrderWebhook.call(
            order: @order,
            event_type: "order.refunded",
            from_status: previous_status,
            to_status: @order.status,
            extra: { refund_amount_cents: @amount_cents, refund_id: refund.id }
          )
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

        remaining = item.quantity - item.stock_restored_quantity.to_i
        next unless remaining.positive?

        target.update!(stock: target.stock + remaining)
        item.update!(stock_restored_quantity: item.quantity)
      end
    end

    def restore_coupon_usage!
      coupon = @order.coupon
      return unless coupon
      return if @order.coupon_usage_restored?

      coupon.decrement!(:used_count) if coupon.used_count.positive?
      @order.update!(coupon_usage_restored: true)
    end

    def restore_gift_card_balance!
      Commerce::RestoreGiftCardBalance.call(order: @order)
    end

    def format_refund_amount(cents)
      ActionController::Base.helpers.number_to_currency(cents / 100.0, unit: "¥")
    end
  end
end
