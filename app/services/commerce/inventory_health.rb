# frozen_string_literal: true

module Commerce
  class InventoryHealth < ApplicationService
    def call
      targets = Product.where.not(stock: nil).order(:name).to_a +
        ProductVariant.where.not(stock: nil).includes(:product).order(:store_product_id, :name).to_a
      rows = targets.map { |target| target_payload(target) }

      ServiceResult.success(
        summary: {
          targets: rows.size,
          available: rows.sum { |row| row.fetch(:available).to_i },
          reserved: rows.sum { |row| row.fetch(:reserved).to_i },
          sold: rows.sum { |row| row.fetch(:sold).to_i },
          anomalies: rows.count { |row| row.fetch(:anomalies).any? }
        },
        targets: rows,
        expired_reservations: expired_reservations,
        mismatched_reservations: mismatched_reservations
      )
    end

    private

    def target_payload(target)
      movements = InventoryMovement.where(target:).order(created_at: :desc).limit(8)
      reserved = InventoryReservation.active.where(target:).sum(:quantity)
      sold = InventoryMovement.where(target:).sum(:sold_delta)
      anomalies = []
      anomalies << "negative_stock" if target.stock.negative?
      anomalies << "expired_reservation" if InventoryReservation.due.where(target:).exists?
      anomalies << "order_state_mismatch" if mismatched_scope.where(target:).exists?

      {
        id: target_identifier(target),
        target_type: target.is_a?(Product) ? "product" : "variant",
        target_id: target.is_a?(Product) ? target.public_id : target.id.to_s,
        name: target_name(target),
        sku: target.respond_to?(:sku) ? target.sku : nil,
        available: target.stock,
        reserved:,
        sold:,
        anomalies:,
        movements: movements.map { |movement| movement_payload(movement) }
      }
    end

    def expired_reservations
      InventoryReservation.due.includes(:order, :order_item).limit(100).map do |reservation|
        reservation_payload(reservation, "expired_reservation")
      end
    end

    def mismatched_reservations
      mismatched_scope.includes(:order, :order_item).limit(100).map do |reservation|
        reservation_payload(reservation, "order_state_mismatch")
      end
    end

    def mismatched_scope
      InventoryReservation.active
        .joins(:order)
        .where.not(store_orders: { status: %w[pending awaiting_payment] })
    end

    def reservation_payload(reservation, anomaly)
      {
        id: reservation.id,
        order_id: reservation.order.public_id,
        order_number: reservation.order.order_number,
        target_id: target_identifier(reservation.target),
        quantity: reservation.quantity,
        status: reservation.status,
        expires_at: reservation.expires_at.iso8601,
        anomaly:
      }
    end

    def movement_payload(movement)
      {
        id: movement.public_id,
        type: movement.movement_type,
        quantity: movement.quantity,
        available_delta: movement.available_delta,
        reserved_delta: movement.reserved_delta,
        sold_delta: movement.sold_delta,
        available_after: movement.available_after,
        reserved_after: movement.reserved_after,
        sold_after: movement.sold_after,
        reason: movement.reason,
        created_at: movement.created_at.iso8601
      }
    end

    def target_identifier(target)
      target.is_a?(Product) ? "product:#{target.public_id}" : "variant:#{target.id}"
    end

    def target_name(target)
      return target.name if target.is_a?(Product)

      "#{target.product.name} · #{target.name}"
    end
  end
end
