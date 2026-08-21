# frozen_string_literal: true

module Commerce
  class CancelOrder < ApplicationService
    def initialize(order:, actor: nil, reason: nil)
      @order = order
      @actor = actor
      @reason = reason.to_s.strip.presence
    end

    def call
      cancelled = false
      previous_status = nil
      inventory_error = nil

      Commerce::Order.transaction do
        @order.lock!
        @order.reload

        unless @order.pending? || @order.awaiting_payment?
          next
        end

        unless @order.may_cancel?
          next
        end

        active_payments = @order.payment_records
          .where(status: Commerce::PrepareOrderPayment::ACTIVE_STATUSES)
          .order(:id)
          .lock
          .to_a

        previous_status = @order.status
        @order.cancel!
        stock_result = restore_stock!
        unless stock_result.success?
          inventory_error = stock_result.error || "inventory_release_failed"
          raise ActiveRecord::Rollback
        end
        restore_coupon_usage!
        restore_gift_card_balance_if_debited!
        restore_store_credit_if_debited!
        cancel_pending_payments!(active_payments)
        cancelled = true
      end

      return ServiceResult.failure(error: inventory_error) if inventory_error
      return ServiceResult.failure(error: "order_cannot_cancel") unless cancelled

      if @reason.present?
        cancel_event = @order.events.where(event_type: "cancel").order(created_at: :desc).first
        cancel_event&.update!(
          actor: @actor || @order.user,
          metadata: (cancel_event.metadata || {}).merge("reason" => @reason)
        )
      end

      MailDeliveryJob.perform_later("Commerce::OrderMailer", "order_cancelled", "deliver_now", args: [ @order.id ])

      Commerce::InAppNotification.order_event(
        user: @order.user,
        notification_type: "commerce.order_cancelled",
        key: "order_cancelled",
        order: @order
      )

      Commerce::DispatchOrderWebhook.call(
        order: @order,
        event_type: "order.cancelled",
        from_status: previous_status,
        to_status: "cancelled",
        extra: { cancel_reason: @reason }
      )

      ServiceResult.success(@order)
    rescue ActiveRecord::RecordInvalid, AASM::InvalidTransition
      ServiceResult.failure(error: "order_cannot_cancel")
    end

    private

    def restore_stock!
      reservation_result = Commerce::ReleaseInventoryReservations.call(
        order: @order,
        reason: @reason || "order_cancelled",
        expired: @reason.in?(%w[expired inventory_reservation_expired])
      )
      return reservation_result unless reservation_result.success?
      return reservation_result unless reservation_result.value.fetch(:legacy)

      @order.items.includes(:product, :variant).find_each do |item|
        target = item.variant || item.product
        Commerce::IncrementStock.call(target: target, quantity: item.quantity)
      end
      ServiceResult.success(legacy: true)
    end

    def restore_coupon_usage!
      order = @order.reload
      coupon = order.coupon
      return unless coupon
      return if order.coupon_usage_restored?
      return unless coupon.used_count.positive?

      coupon.decrement!(:used_count)
      order.update!(coupon_usage_restored: true)
    end

    def cancel_pending_payments!(payments)
      payments.each do |payment|
        payment.update!(status: "failed") if payment.pending? || payment.processing?
      end
    end

    def restore_gift_card_balance_if_debited!
      card = @order.gift_card
      return unless card
      return unless card.transactions.exists?(order: @order, transaction_type: :debit)

      Commerce::RestoreGiftCardBalance.call(order: @order)
    end

    def restore_store_credit_if_debited!
      return unless Commerce::StoreCreditTransaction.where(order: @order).where("amount_cents < 0").exists?

      Commerce::RestoreStoreCredit.call(order: @order)
    end
  end
end
