# frozen_string_literal: true

module Commerce
  class RestoreStockPartial < ApplicationService
    def initialize(order:, refund_amount_cents:, payment_amount_cents:)
      @order = order
      @refund_amount_cents = refund_amount_cents.to_i
      @payment_amount_cents = payment_amount_cents.to_i
    end

    def call
      return ServiceResult.success(restored_units: 0) unless @payment_amount_cents.positive?

      ratio = @refund_amount_cents.to_f / @payment_amount_cents
      restored_units = 0

      @order.items.includes(:product, :variant).find_each do |item|
        target = item.variant || item.product
        next if target.stock.nil?

        remaining = item.quantity - item.stock_restored_quantity.to_i
        next unless remaining.positive?

        restore_qty = (remaining * ratio).round
        restore_qty = [ restore_qty, remaining ].min
        next unless restore_qty.positive?

        target.update!(stock: target.stock + restore_qty)
        item.update!(stock_restored_quantity: item.stock_restored_quantity.to_i + restore_qty)
        restored_units += restore_qty
      end

      ServiceResult.success(restored_units: restored_units)
    end
  end
end
