# frozen_string_literal: true

module Commerce
  class RestoreStockPartial < ApplicationService
    def initialize(order:, refund_amount_cents:, payment_amount_cents:, already_refunded_cents: 0)
      @order = order
      @refund_amount_cents = refund_amount_cents.to_i
      @payment_amount_cents = payment_amount_cents.to_i
      @already_refunded_cents = already_refunded_cents.to_i
    end

    def call
      return ServiceResult.success(restored_units: 0) unless @payment_amount_cents.positive?

      restored_units = 0

      Commerce::Order.transaction do
        @order.lock!
        @order.reload

        @order.items.includes(:product, :variant).find_each do |item|
          target = item.variant || item.product
          next if target.stock.nil?

          already_restored = item.stock_restored_quantity.to_i
          remaining = item.quantity - already_restored
          next unless remaining.positive?

          target_restored = cumulative_target(item.quantity)
          restore_qty = [ target_restored - already_restored, remaining ].min
          next unless restore_qty.positive?

          Commerce::IncrementStock.call(target: target, quantity: restore_qty)
          item.update!(stock_restored_quantity: already_restored + restore_qty)
          restored_units += restore_qty
        end
      end

      ServiceResult.success(restored_units: restored_units)
    end

    private

    def cumulative_target(quantity)
      total_refunded = [ @already_refunded_cents + @refund_amount_cents, @payment_amount_cents ].min
      (quantity * total_refunded.to_f / @payment_amount_cents).round
    end
  end
end
