# frozen_string_literal: true

module Commerce
  class CancelOrder < ApplicationService
    def initialize(order:, actor: nil)
      @order = order
      @actor = actor
    end

    def call
      return ServiceResult.failure(error: "Order cannot be cancelled.") unless @order.pending? || @order.awaiting_payment?

      from_status = @order.status
      Commerce::Order.transaction do
        @order.cancel! if @order.may_cancel?
        restore_stock!
      end

      Commerce::OrderEvent.create!(
        order: @order,
        event_type: "cancelled",
        from_status: from_status,
        to_status: "cancelled",
        actor: @actor
      )

      MailDeliveryJob.perform_later("Commerce::OrderMailer", "order_cancelled", "deliver_now", args: [ @order.id ])

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
  end
end
