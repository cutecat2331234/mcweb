# frozen_string_literal: true

module Commerce
  class ReserveInventory < ApplicationService
    def initialize(order_item:, expires_at: nil)
      @order_item = order_item
      @target = order_item.variant || order_item.product
      @expires_at = expires_at || order_item.order.payment_expires_at || 30.minutes.from_now
    end

    def call
      return ServiceResult.success(reservation: nil, unlimited: true) if @target.stock.nil?

      reservation = InventoryReservation.find_by(order_item: @order_item)
      return ServiceResult.success(reservation:, replayed: true) if reservation

      InventoryReservation.transaction do
        @target.lock!
        @target.reload
        if @target.stock < @order_item.quantity && !@order_item.product.allow_backorder?
          return ServiceResult.failure(error: "stock_insufficient", code: "stock_insufficient")
        end

        @target.update!(stock: @target.stock - @order_item.quantity)
        reservation = InventoryReservation.create!(
          order: @order_item.order,
          order_item: @order_item,
          target: @target,
          quantity: @order_item.quantity,
          idempotency_key: "order-item:#{@order_item.id}:reserve",
          expires_at: @expires_at,
          reserved_at: Time.current
        )
        movement = InventoryMovement.record!(
          target: @target,
          reservation:,
          movement_type: "reserve",
          quantity: reservation.quantity,
          available_delta: -reservation.quantity,
          reserved_delta: reservation.quantity,
          idempotency_key: "inventory-reservation:#{reservation.id}:reserve"
        )
        Commerce::DomainEvents.publish_after_commit(
          "commerce.inventory.reserved",
          Commerce::DomainEvents.inventory(movement)
        )
      end

      ServiceResult.success(reservation:, replayed: false)
    rescue ActiveRecord::RecordNotUnique
      reservation = InventoryReservation.find_by!(order_item: @order_item)
      ServiceResult.success(reservation:, replayed: true)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
