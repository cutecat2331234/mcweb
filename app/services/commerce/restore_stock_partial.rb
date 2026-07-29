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
      restore_error = nil

      Commerce::Order.transaction do
        @order.lock!
        @order.reload

        entries = @order.items.includes(:product, :variant).order(:id).filter_map do |item|
          target = item.variant || item.product
          next if target.stock.nil?

          [ item, target ]
        end

        entries
          .map(&:last)
          .uniq { |target| [ target.class.table_name, target.id ] }
          .sort_by { |target| [ target.class.table_name, target.id ] }
          .each(&:lock!)

        entries.each do |item, target|
          item.lock!
          already_restored = item.stock_restored_quantity.to_i
          remaining = item.quantity - already_restored
          next unless remaining.positive?

          target_restored = cumulative_target(item.quantity)
          restore_qty = [ target_restored - already_restored, remaining ].min
          next unless restore_qty.positive?

          target.reload
          unless target.stock
            restore_error = "stock_target_invalid"
            raise ActiveRecord::Rollback
          end

          target.update!(stock: target.stock + restore_qty)
          item.update!(stock_restored_quantity: already_restored + restore_qty)
          InventoryMovement.record!(
            target:,
            reservation: item.inventory_reservation,
            order: @order,
            order_item: item,
            movement_type: "refund",
            quantity: restore_qty,
            available_delta: restore_qty,
            sold_delta: -restore_qty,
            idempotency_key: "order-item:#{item.id}:refund-restored:#{already_restored + restore_qty}"
          )
          restored_units += restore_qty
        end
      end

      return ServiceResult.failure(error: restore_error) if restore_error

      ServiceResult.success(restored_units: restored_units)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def cumulative_target(quantity)
      Commerce::CumulativeRefundAllocation.target(
        total_units: quantity,
        refunded_cents: @already_refunded_cents + @refund_amount_cents,
        payment_cents: @payment_amount_cents
      )
    end
  end
end
