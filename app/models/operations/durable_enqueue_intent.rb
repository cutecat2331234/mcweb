# frozen_string_literal: true

module Operations
  class DurableEnqueueIntent < ApplicationRecord
    self.table_name = "operations_durable_enqueue_intents"

    has_many :attempts,
             class_name: "Operations::DurableEnqueueAttempt",
             foreign_key: :intent_id,
             dependent: :restrict_with_error,
             inverse_of: :intent
    has_many :events,
             class_name: "Operations::DurableEnqueueEvent",
             foreign_key: :intent_id,
             dependent: :restrict_with_error,
             inverse_of: :intent

    validates :public_id,
              presence: true,
              uniqueness: true,
              format: { with: /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i }
    validates :handler_key,
              presence: true,
              length: { maximum: 120 },
              format: { with: Operations::DurableEnqueueRegistry::KEY_PATTERN }
    validates :source_kind,
              presence: true,
              length: { maximum: 120 },
              format: { with: Operations::DurableEnqueueRegistry::SOURCE_KIND_PATTERN }
    validates :source_id, numericality: { only_integer: true, greater_than: 0 }
    validates :dedupe_key,
              presence: true,
              length: { maximum: 191 },
              uniqueness: { scope: :handler_key }
    validates :queue_name,
              presence: true,
              length: { maximum: 64 },
              inclusion: { in: ApplicationJob::QUEUE_NAMES.values }
    validates :arguments_sha256, format: { with: /\A[0-9a-f]{64}\z/ }
    validates :requested_at, presence: true
    validate :arguments_are_a_bounded_mapping

    before_validation :assign_public_id, on: :create

    def readonly?
      persisted?
    end

    def terminal?
      events.order(sequence: :desc).limit(1).pick(:event_type)
            .in?(Operations::DurableEnqueueEvent::TERMINAL_EVENT_TYPES)
    end

    private

    def assign_public_id
      self.public_id ||= SecureRandom.uuid
    end

    def arguments_are_a_bounded_mapping
      unless arguments.is_a?(Hash)
        errors.add(:arguments, :invalid)
        return
      end

      errors.add(:arguments, :too_long) if ActiveSupport::JSON.encode(arguments).bytesize > 8.kilobytes
    end
  end
end
