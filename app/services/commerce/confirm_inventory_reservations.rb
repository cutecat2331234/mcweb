# frozen_string_literal: true

module Commerce
  class ConfirmInventoryReservations < ApplicationService
    def initialize(order:)
      @order = order
    end

    def call
      reservations = InventoryReservation.where(order: @order).order(:id).to_a
      InventoryReservation.transaction do
        reservations.each do |reservation|
          reservation.lock!
          next if reservation.confirmed?
          return ServiceResult.failure(error: "inventory_reservation_released") unless reservation.active?

          reservation.update!(status: :confirmed, confirmed_at: Time.current)
          movement = InventoryMovement.record!(
            target: reservation.target,
            reservation:,
            movement_type: "confirm",
            quantity: reservation.quantity,
            reserved_delta: -reservation.quantity,
            sold_delta: reservation.quantity,
            idempotency_key: "inventory-reservation:#{reservation.id}:confirm"
          )
          Commerce::DomainEvents.publish_after_commit(
            "commerce.inventory.confirmed",
            Commerce::DomainEvents.inventory(movement)
          )
        end
      end

      ServiceResult.success(reservations:)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
