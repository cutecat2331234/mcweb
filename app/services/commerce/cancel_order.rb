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

      Commerce::Order.transaction do
        @order.lock!
        @order.reload

        unless @order.pending? || @order.awaiting_payment?
          next
        end

        unless @order.may_cancel?
          next
        end

        previous_status = @order.status
        @order.cancel!
        restore_stock!
        restore_coupon_usage!
        restore_gift_card_balance_if_debited!
        restore_store_credit_if_debited!
        cancel_pending_payments!
        cancelled = true
      end

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
      @order.items.includes(:product, :variant).find_each do |item|
        target = item.variant || item.product
        next if target.stock.nil?

        target.update!(stock: target.stock + item.quantity)
      end
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

    def cancel_pending_payments!
      @order.payment_records.where(status: %w[pending processing]).update_all(status: "failed", updated_at: Time.current)
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
