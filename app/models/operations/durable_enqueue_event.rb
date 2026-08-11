# frozen_string_literal: true

module Operations
  class DurableEnqueueEvent < ApplicationRecord
    self.table_name = "operations_durable_enqueue_events"

    EVENT_TYPES = %w[
      recorded
      enqueue_requested
      enqueue_succeeded
      enqueue_failed
      attempt_started
      lease_renewed
      attempt_succeeded
      attempt_skipped
      attempt_failed
      lease_expired
      retry_scheduled
      dead_lettered
      reopened
    ].freeze
    ATTEMPT_EVENT_TYPES = %w[
      attempt_started lease_renewed attempt_succeeded attempt_skipped attempt_failed lease_expired
    ].freeze
    ERROR_EVENT_TYPES = %w[
      enqueue_failed attempt_failed retry_scheduled dead_lettered attempt_skipped
    ].freeze
    TERMINAL_EVENT_TYPES = %w[attempt_succeeded attempt_skipped dead_lettered].freeze

    belongs_to :intent,
               class_name: "Operations::DurableEnqueueIntent",
               inverse_of: :events
    belongs_to :attempt,
               class_name: "Operations::DurableEnqueueAttempt",
               optional: true,
               inverse_of: :events

    validates :sequence,
              numericality: { only_integer: true, greater_than: 0 },
              uniqueness: { scope: :intent_id }
    validates :generation, numericality: { only_integer: true, greater_than: 0 }
    validates :event_type, inclusion: { in: EVENT_TYPES }
    validates :error_code,
              allow_nil: true,
              length: { maximum: 120 },
              format: { with: /\A[a-z][a-z0-9_]*\z/ }
    validates :occurred_at, presence: true
    validate :metadata_is_a_bounded_mapping
    validate :event_shape_is_valid

    scope :terminal, -> { where(event_type: TERMINAL_EVENT_TYPES) }

    def readonly?
      persisted?
    end

    private

    def metadata_is_a_bounded_mapping
      unless metadata.is_a?(Hash)
        errors.add(:metadata, :invalid)
        return
      end

      errors.add(:metadata, :too_long) if ActiveSupport::JSON.encode(metadata).bytesize > 4.kilobytes
    end

    def event_shape_is_valid
      errors.add(:attempt, :invalid) if ATTEMPT_EVENT_TYPES.include?(event_type) != attempt.present?
      errors.add(:error_code, :invalid) if ERROR_EVENT_TYPES.include?(event_type) != error_code.present?
      errors.add(:available_at, :invalid) if (event_type == "retry_scheduled") != available_at.present?
      lease_shape_valid = event_type == "lease_renewed" ? lease_expires_at.present? : lease_expires_at.nil?
      errors.add(:lease_expires_at, :invalid) unless lease_shape_valid
      if event_type == "lease_renewed" && occurred_at && lease_expires_at && lease_expires_at <= occurred_at
        errors.add(:lease_expires_at, :greater_than, count: occurred_at)
      end
      return unless attempt

      errors.add(:attempt, :invalid) if intent_id && attempt.intent_id != intent_id
      errors.add(:generation, :invalid) if attempt.generation != generation
      validate_lease_expiry_time if event_type == "lease_expired"
    end

    def validate_lease_expiry_time
      renewal_expiry = attempt.events
        .where(event_type: "lease_renewed")
        .maximum(:lease_expires_at)
      effective_expiry = [ attempt.lease_expires_at, renewal_expiry ].compact.max
      return unless occurred_at && effective_expiry && occurred_at < effective_expiry

      errors.add(:occurred_at, :greater_than_or_equal_to, count: effective_expiry)
    end
  end
end
