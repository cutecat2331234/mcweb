# frozen_string_literal: true

module Commerce
  class ReleaseInventoryReservations < ApplicationService
    def initialize(order:, reason:, expired: false)
      @order = order
      @reason = reason.to_s
      @expired = expired
    end

    def call
      reservations = InventoryReservation.where(order: @order).order(:target_type, :target_id, :id).to_a
      return ServiceResult.success(reservations: [], legacy: true) if reservations.empty?

      released = []
      InventoryReservation.transaction do
        reservations.each do |reservation|
          reservation.lock!
          next if reservation.released? || reservation.expired?
          return ServiceResult.failure(error: "inventory_reservation_confirmed") if reservation.confirmed?

          target = reservation.target
          target.lock!
          target.reload
          target.update!(stock: target.stock + reservation.quantity)
          status = @expired ? :expired : :released
          reservation.update!(
            status:,
            released_at: Time.current,
            release_reason: @reason
          )
          movement = InventoryMovement.record!(
            target:,
            reservation:,
            movement_type: @expired ? "expire" : "release",
            quantity: reservation.quantity,
            available_delta: reservation.quantity,
            reserved_delta: -reservation.quantity,
            idempotency_key: "inventory-reservation:#{reservation.id}:#{status}",
            reason: @reason
          )
          Commerce::DomainEvents.publish_after_commit(
            "commerce.inventory.released",
            Commerce::DomainEvents.inventory(movement)
          )
          released << reservation
        end
      end

      ServiceResult.success(reservations: released, legacy: false)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
