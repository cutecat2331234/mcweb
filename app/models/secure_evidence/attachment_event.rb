# frozen_string_literal: true

module SecureEvidence
  class AttachmentEvent < ApplicationRecord
    self.table_name = "secure_evidence_attachment_events"

    EVENT_TYPES = %w[
      created scan_clean scan_infected scan_error downloaded retention_extended
      cleanup_scheduled cleanup_failed purged
    ].freeze

    belongs_to :attachment,
      class_name: "SecureEvidence::Attachment",
      foreign_key: :secure_evidence_attachment_id,
      inverse_of: :events
    belongs_to :actor, class_name: "User", optional: true

    validates :event_type, inclusion: { in: EVENT_TYPES }
    validates :idempotency_key,
      presence: true,
      uniqueness: true,
      format: { with: /\A[A-Za-z0-9:._-]{8,180}\z/ }
    validates :occurred_at, presence: true
    validate :metadata_is_mapping

    before_update :prevent_mutation
    before_destroy :prevent_mutation

    scope :timeline, -> { order(:occurred_at, :id) }

    private

    def metadata_is_mapping
      errors.add(:metadata, :invalid) unless metadata.is_a?(Hash)
    end

    def prevent_mutation
      errors.add(:base, :immutable)
      throw(:abort)
    end
  end
end
