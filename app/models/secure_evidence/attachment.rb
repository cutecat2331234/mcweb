# frozen_string_literal: true

module SecureEvidence
  class Attachment < ApplicationRecord
    self.table_name = "secure_evidence_attachments"

    include HasPublicId

    STATES = %w[pending available quarantined purge_pending purged].freeze
    IMMUTABLE_FIELDS = %w[
      public_id uploader_id uploader_public_id_snapshot subject_key subject_id
      subject_public_id idempotency_key request_fingerprint filename content_type
      byte_size sha256 created_at
    ].freeze

    belongs_to :uploader, class_name: "User"
    has_one :upload_record,
      class_name: "Community::Upload",
      foreign_key: :secure_evidence_attachment_id,
      inverse_of: :secure_evidence_attachment
    has_many :events,
      class_name: "SecureEvidence::AttachmentEvent",
      foreign_key: :secure_evidence_attachment_id,
      inverse_of: :attachment

    enum :state, STATES.index_by(&:itself), validate: true, prefix: true

    validates :uploader_public_id_snapshot,
      :subject_key,
      :subject_public_id,
      :idempotency_key,
      :request_fingerprint,
      :filename,
      :content_type,
      :sha256,
      :retention_until,
      presence: true
    validates :subject_key, format: { with: SubjectRegistry::KEY_PATTERN }
    validates :subject_id, numericality: { only_integer: true, greater_than: 0 }
    validates :byte_size,
      numericality: {
        only_integer: true,
        greater_than: 0,
        less_than_or_equal_to: SubjectRegistry::HARD_MAX_FILE_BYTES
      }
    validates :sha256, :request_fingerprint, format: { with: /\A[0-9a-f]{64}\z/ }
    validates :idempotency_key, format: { with: /\A[A-Za-z0-9:_-]{8,100}\z/ }
    validate :retention_window_valid
    validate :state_shape_valid
    validate :immutable_identity, on: :update
    before_destroy :prevent_destroy

    scope :retention_due, ->(at = Time.current) {
      where(state: %w[pending available quarantined])
        .where(retention_until: ..at)
    }

    def blob
      upload_record&.blob
    end

    def scan_status
      upload_record&.scan_status || "pending"
    end

    private

    def retention_window_valid
      return unless retention_until && created_at

      unless retention_until >= created_at + 1.hour && retention_until <= created_at + 10.years
        errors.add(:retention_until, :invalid)
      end
    end

    def state_shape_valid
      errors.add(:scanned_at, :blank) if state_available? && scanned_at.blank?
      errors.add(:quarantined_at, :blank) if state_quarantined? && quarantined_at.blank?
      if state_purged? != purged_at.present?
        errors.add(:purged_at, :invalid)
      end
      errors.add(:scanned_at, :invalid) if scanned_at && created_at && scanned_at < created_at
      if quarantined_at && (!scanned_at || quarantined_at < scanned_at)
        errors.add(:quarantined_at, :invalid)
      end
      errors.add(:purged_at, :invalid) if purged_at && created_at && purged_at < created_at
    end

    def immutable_identity
      return if (changes_to_save.keys & IMMUTABLE_FIELDS).empty?

      errors.add(:base, :immutable)
    end

    def prevent_destroy
      errors.add(:base, :immutable)
      throw(:abort)
    end
  end
end
