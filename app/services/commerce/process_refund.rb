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
      amount_error = nil

      Commerce::Refund.transaction do
        @order.lock!
        @payment_record.lock!
        @payment_record.reload

        unless @payment_record.status == "succeeded"
          amount_error = "Payment is not refundable."
          raise ActiveRecord::Rollback
        end

        refunded_cents = @order.refunds.where(status: %w[pending completed]).where.not(id: @existing_refund&.id).sum(:amount_cents)
        remaining = @payment_record.amount_cents - refunded_cents
        if @amount_cents > remaining
          amount_error = "Refund amount exceeds remaining balance."
          raise ActiveRecord::Rollback
        end

        refund = find_or_build_refund
        refund.assign_attributes(
          amount_cents: @amount_cents,
          reason: @reason.presence || refund.reason,
          approved_by: @approved_by || refund.approved_by
        )
        refund.save!
      end

      return ServiceResult.failure(error: amount_error) if amount_error.present?
      return ServiceResult.failure(error: "Unable to prepare refund.") unless refund&.persisted?

      provider = Payments::Provider.for(@payment_record.provider)
      provider_result = provider.process_refund(refund)

      restore_error = [ nil ]
      provider_failure = nil
      success_refund = nil
      success_previous_status = nil

      Commerce::Refund.transaction do
        @order.lock!
        @payment_record.lock!
        refund.lock!
        refund.reload

        previous_status = @order.status
        refunded_cents = @order.refunds.where(status: %w[pending completed]).where.not(id: refund.id).sum(:amount_cents)

        if provider_result.success?
          apply_refund_success!(refund, previous_status, refunded_cents, restore_error)
          success_refund = refund
          success_previous_status = previous_status
        else
          refund.update!(status: "rejected")
          Commerce::OrderEvent.create!(
            order: @order,
            actor: @approved_by,
            event_type: "refund_rejected",
            metadata: { refund_id: refund.id, reason: provider_result.error }
          )
          provider_failure = provider_result
        end
      end

      return provider_failure if provider_failure
      return ServiceResult.failure(error: restore_error[0]) if restore_error[0].present?

      deliver_refund_notifications!(success_refund, success_previous_status)
      Administration::AuditLogger.call(
        actor: @approved_by || @requested_by,
        action: "commerce.refund_processed",
        resource: success_refund,
        metadata: { amount_cents: @amount_cents }
      )

      ServiceResult.success(success_refund)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def apply_refund_success!(refund, previous_status, refunded_cents, restore_error)
      refund.update!(status: "completed") unless refund.completed?
      Commerce::OrderEvent.create!(
        order: @order,
        actor: @approved_by || @requested_by,
        event_type: "refund_processed",
        metadata: { refund_id: refund.id, amount_cents: @amount_cents }
      )
      ensure_restore!(
        Commerce::RestoreStoreCreditPartial.call(
          order: @order,
          refund_amount_cents: @amount_cents,
          payment_amount_cents: @payment_record.amount_cents
        ),
        restore_error,
        I18n.t("mcweb.services.errors.store_credit_restore_failed")
      )
      ensure_restore!(
        Commerce::RestoreStockPartial.call(
          order: @order,
          refund_amount_cents: @amount_cents,
          payment_amount_cents: @payment_record.amount_cents
        ),
        restore_error,
        I18n.t("mcweb.services.errors.stock_restore_failed")
      )
      ensure_restore!(
        Commerce::RestoreCouponPartial.call(
          order: @order,
          refund_amount_cents: @amount_cents,
          payment_amount_cents: @payment_record.amount_cents,
          already_refunded_cents: refunded_cents
        ),
        restore_error,
        I18n.t("mcweb.services.errors.coupon_restore_failed")
      )
      ensure_restore!(
        Commerce::RestoreGiftCardPartial.call(
          order: @order,
          refund_amount_cents: @amount_cents,
          payment_amount_cents: @payment_record.amount_cents
        ),
        restore_error,
        I18n.t("mcweb.services.errors.gift_card_balance_restore_failed")
      )
      return unless full_refund?(@amount_cents, refunded_cents)

      unless @order.may_refund?
        restore_error[0] = I18n.t("mcweb.services.errors.order_refund_status_failed")
        raise ActiveRecord::Rollback
      end

      @order.refund!
      restore_stock!
      restore_coupon_usage!
      ensure_restore!(
        restore_gift_card_balance!,
        restore_error,
        I18n.t("mcweb.services.errors.gift_card_balance_restore_failed")
      )
      ensure_restore!(
        Commerce::RestoreStoreCredit.call(order: @order),
        restore_error,
        I18n.t("mcweb.services.errors.store_credit_restore_failed")
      )
      ensure_restore!(
        Commerce::RevokeIssuedGiftCards.call(order: @order),
        restore_error,
        I18n.t("mcweb.services.errors.gift_card_revoke_failed")
      )
            ensure_restore!(
              Commerce::RevokeMembershipsForOrder.call(order: @order),
              restore_error,
              I18n.t("mcweb.services.errors.membership_revoke_failed")
            )
    end

    def deliver_refund_notifications!(refund, previous_status)
      MailDeliveryJob.perform_later("Commerce::OrderMailer", "refund_processed", "deliver_now", args: [ refund.id ])
      Commerce::NotifyOrderEvent.call(
        user: @order.user,
        notification_type: "commerce.refund_processed",
        title: I18n.t("mcweb.labels.notification_types.commerce.refund_processed"),
        body: [
          I18n.t("mcweb.mail.order.refund_processed.body", number: @order.order_number),
          I18n.t("mcweb.mail.order.refund_processed.amount", amount: format_refund_amount(@amount_cents))
        ].join(" "),
        path: "/app/store/orders/#{@order.public_id}"
      )
      Commerce::DispatchOrderWebhook.call(
        order: @order,
        event_type: "order.refunded",
        from_status: previous_status,
        to_status: @order.status,
        extra: { refund_amount_cents: @amount_cents, refund_id: refund.id }
      )
    end

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

        Commerce::IncrementStock.call(target: target, quantity: remaining)
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

    def ensure_restore!(result, restore_error, message)
      return if result.success?

      restore_error[0] = result.error.presence || message
      raise ActiveRecord::Rollback
    end
  end
end
