module Commerce
  class Refund < ApplicationRecord
    RESERVED_STATUSES = %w[pending approved completed].freeze
    IN_FLIGHT_STATUSES = %w[pending approved].freeze

    belongs_to :order, class_name: "Commerce::Order", foreign_key: :store_order_id
    belongs_to :payment_record, class_name: "Payments::Record"
    belongs_to :requested_by, class_name: "User", optional: true
    belongs_to :approved_by, class_name: "User", optional: true

    enum :status, { pending: "pending", approved: "approved", rejected: "rejected", completed: "completed" }, validate: true

    validates :amount_cents, numericality: { greater_than: 0 }

    scope :reserved, -> { where(status: RESERVED_STATUSES) }
    scope :in_flight, -> { where(status: IN_FLIGHT_STATUSES) }

    def approve!(by:)
      update!(status: :approved, approved_by: by)
    end

    def complete!
      update!(status: :completed)
    end
  end
end
