# frozen_string_literal: true

module Commerce
  class CancelOrder < ApplicationService
    def initialize(order:, actor: nil, reason: nil)
      @order = order
      @actor = actor
      @reason = reason.to_s.strip.presence
    end

    def call
      return ServiceResult.failure(error: "Order cannot be cancelled.") unless @order.pending? || @order.awaiting_payment?

      previous_status = @order.status
      Commerce::Order.transaction do
        @order.cancel! if @order.may_cancel?
        restore_stock!
      end

      Commerce::OrderEvent.create!(
        order: @order,
        actor: @actor || @order.user,
        event_type: "cancelled",
        metadata: { reason: @reason }.compact
      ) if @reason.present?

      MailDeliveryJob.perform_later("Commerce::OrderMailer", "order_cancelled", "deliver_now", args: [ @order.id ])

      Commerce::NotifyOrderEvent.call(
        user: @order.user,
        notification_type: "commerce.order_cancelled",
        title: "订单已取消",
        body: "订单 #{@order.order_number} 已取消。",
        path: "/app/store/orders/#{@order.public_id}"
      )

      Commerce::DispatchOrderWebhook.call(
        order: @order,
        event_type: "order.cancelled",
        from_status: previous_status,
        to_status: "cancelled",
        extra: { cancel_reason: @reason }
      )

      restore_coupon_usage!
      cancel_pending_payments!

      ServiceResult.success(@order)
    rescue ActiveRecord::RecordInvalid, AASM::InvalidTransition => e
      ServiceResult.failure(error: e.message)
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
      coupon = @order.coupon
      return unless coupon
      return if @order.coupon_usage_restored?
      return unless coupon.used_count.positive?

      coupon.decrement!(:used_count)
      @order.update!(coupon_usage_restored: true)
    end

    def cancel_pending_payments!
      @order.payment_records.where(status: "pending").update_all(status: "failed", updated_at: Time.current)
    end
  end
end
