# frozen_string_literal: true

module Commerce
  class InventoryReservation < ApplicationRecord
    self.table_name = "store_inventory_reservations"

    belongs_to :order, class_name: "Commerce::Order", foreign_key: :store_order_id
    belongs_to :order_item, class_name: "Commerce::OrderItem", foreign_key: :store_order_item_id
    belongs_to :target, polymorphic: true
    has_many :movements,
             class_name: "Commerce::InventoryMovement",
             foreign_key: :store_inventory_reservation_id,
             dependent: :restrict_with_error

    enum :status, {
      active: "active",
      confirmed: "confirmed",
      released: "released",
      expired: "expired"
    }, validate: true

    validates :quantity, numericality: { only_integer: true, greater_than: 0 }
    validates :idempotency_key, presence: true, uniqueness: true
    validates :order_item, uniqueness: true

    scope :due, ->(at = Time.current) { active.where("expires_at <= ?", at) }
  end
end
