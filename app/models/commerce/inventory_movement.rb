# frozen_string_literal: true

module Commerce
  class InventoryMovement < ApplicationRecord
    self.table_name = "store_inventory_movements"

    include HasPublicId

    belongs_to :target, polymorphic: true
    belongs_to :reservation,
               class_name: "Commerce::InventoryReservation",
               foreign_key: :store_inventory_reservation_id,
               optional: true
    belongs_to :order, class_name: "Commerce::Order", foreign_key: :store_order_id, optional: true
    belongs_to :order_item, class_name: "Commerce::OrderItem", foreign_key: :store_order_item_id, optional: true
    belongs_to :actor, class_name: "User", optional: true

    MOVEMENT_TYPES = %w[reserve confirm release expire refund damage adjustment recovery].freeze

    validates :movement_type, inclusion: { in: MOVEMENT_TYPES }
    validates :quantity, numericality: { only_integer: true, greater_than: 0 }
    validates :idempotency_key, presence: true, uniqueness: true

    def readonly?
      persisted?
    end

    def self.record!(target:, movement_type:, quantity:, idempotency_key:, reservation: nil, order: nil,
                     order_item: nil, actor: nil, available_delta: 0, reserved_delta: 0, sold_delta: 0,
                     request_id: nil, reason: nil, metadata: {})
      existing = find_by(idempotency_key:)
      return existing if existing

      create!(
        target:,
        reservation:,
        order: order || reservation&.order,
        order_item: order_item || reservation&.order_item,
        actor:,
        movement_type:,
        quantity:,
        idempotency_key:,
        available_delta:,
        reserved_delta:,
        sold_delta:,
        available_after: target.stock,
        reserved_after: where(target:).sum(:reserved_delta) + reserved_delta,
        sold_after: where(target:).sum(:sold_delta) + sold_delta,
        request_id:,
        reason:,
        metadata:
      )
    end
  end
end
