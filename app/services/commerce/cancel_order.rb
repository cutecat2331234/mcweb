# frozen_string_literal: true

module Commerce
  class CancelOrder < ApplicationService
    def initialize(order:, actor: nil)
      @order = order
      @actor = actor
    end

    def call
      return ServiceResult.failure(error: "Order cannot be cancelled.") unless @order.pending? || @order.awaiting_payment?

      Commerce::Order.transaction do
        @order.cancel! if @order.may_cancel?
        restore_stock!
      end

      MailDeliveryJob.perform_later("Commerce::OrderMailer", "order_cancelled", "deliver_now", args: [ @order.id ])

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
      return unless coupon.used_count.positive?

      coupon.decrement!(:used_count)
    end

    def cancel_pending_payments!
      @order.payment_records.where(status: "pending").update_all(status: "failed", updated_at: Time.current)
    end
  end
end
