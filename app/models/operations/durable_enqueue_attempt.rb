# frozen_string_literal: true

module Operations
  class DurableEnqueueAttempt < ApplicationRecord
    self.table_name = "operations_durable_enqueue_attempts"

    TRIGGERS = %w[after_commit maintenance manual].freeze

    belongs_to :intent,
               class_name: "Operations::DurableEnqueueIntent",
               inverse_of: :attempts
    has_many :events,
             class_name: "Operations::DurableEnqueueEvent",
             foreign_key: :attempt_id,
             dependent: :restrict_with_error,
             inverse_of: :attempt

    validates :attempt_number,
              numericality: { only_integer: true, greater_than: 0 },
              uniqueness: { scope: :intent_id }
    validates :generation, numericality: { only_integer: true, greater_than: 0 }
    validates :lease_token,
              presence: true,
              uniqueness: true,
              format: { with: /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i }
    validates :job_id, presence: true, length: { maximum: 160 }
    validates :trigger, inclusion: { in: TRIGGERS }
    validates :started_at, :lease_expires_at, presence: true
    validate :lease_expires_after_start

    def readonly?
      persisted?
    end

    private

    def lease_expires_after_start
      return if started_at.blank? || lease_expires_at.blank? || lease_expires_at > started_at

      errors.add(:lease_expires_at, :greater_than, count: started_at)
    end
  end
end
