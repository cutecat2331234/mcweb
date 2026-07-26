module Commerce
  class Refund < ApplicationRecord
    STALE_PROCESSING_AFTER = 5.minutes
    RESERVED_STATUSES = %w[pending approved completed].freeze
    IN_FLIGHT_STATUSES = %w[pending approved].freeze

    belongs_to :order, class_name: "Commerce::Order", foreign_key: :store_order_id
    belongs_to :payment_record, class_name: "Payments::Record"
    belongs_to :requested_by, class_name: "User", optional: true
    belongs_to :approved_by, class_name: "User", optional: true

    enum :status, {
      pending: "pending",
      approved: "approved",
      rejected: "rejected",
      failed: "failed",
      completed: "completed"
    }, validate: true

    enum :restoration_status, {
      pending: "pending",
      processing: "processing",
      failed: "failed",
      completed: "completed"
    }, validate: true, prefix: :restoration

    validates :amount_cents, numericality: { greater_than: 0 }

    scope :reserved, -> { where(status: RESERVED_STATUSES) }
    scope :in_flight, -> { where(status: IN_FLIGHT_STATUSES) }
    scope :stale_processing, lambda {
      approved.where(
        "COALESCE(processing_started_at, updated_at) < ?",
        STALE_PROCESSING_AFTER.ago
      )
    }

    validates :provider_refund_id, uniqueness: true, allow_nil: true
    validates :restoration_attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    validate :payment_belongs_to_order

    def approve!(by:)
      update!(status: :approved, approved_by: by)
    end

    def complete!
      update!(status: :completed)
    end

    def processing_stale?
      approved? &&
        (processing_started_at || updated_at) < STALE_PROCESSING_AFTER.ago
    end

    def provider_confirmed?
      provider_confirmed_at.present?
    end

    private

    def payment_belongs_to_order
      return if payment_record.nil? || store_order_id.nil?
      return if payment_record.store_order_id == store_order_id

      errors.add(:payment_record, "must belong to the refund order")
    end
  end
end
