# frozen_string_literal: true

module Commerce
  class DisputeEvidence < ApplicationRecord
    self.table_name = "store_dispute_evidence"

    include HasPublicId

    MAX_BYTES = 64.kilobytes
    CONTENT_TYPES = %w[text/plain application/json].freeze
    SUBMISSION_STATUSES = %w[submitted failed purged].freeze
    MUTABLE_AFTER_CREATION = %w[
      content byte_size sha256 submission_status provider_reference
      retention_until purged_at updated_at
    ].freeze

    belongs_to :dispute,
               class_name: "Commerce::Dispute",
               foreign_key: :store_dispute_id
    belongs_to :submitted_by, class_name: "User"

    validates :idempotency_key, :title, :filename, :content_type, :sha256,
              :submitted_at, presence: true
    validates :idempotency_key, uniqueness: true
    validates :content_type, inclusion: { in: CONTENT_TYPES }
    validates :submission_status, inclusion: { in: SUBMISSION_STATUSES }
    validates :byte_size,
              numericality: {
                only_integer: true,
                greater_than_or_equal_to: 0,
                less_than_or_equal_to: MAX_BYTES
              }
    validates :sha256, format: { with: /\A[0-9a-f]{64}\z/ }
    validate :content_matches_snapshot, unless: :purged?
    validate :immutable_snapshot_fields, on: :update

    scope :available, -> { where(purged_at: nil) }
    scope :retention_due, lambda {
      where.not(retention_until: nil)
        .where(purged_at: nil)
        .where(retention_until: ..Time.current)
    }

    def purged?
      purged_at.present? || submission_status == "purged"
    end

    private

    def content_matches_snapshot
      body = content.to_s
      errors.add(:content, I18n.t("mcweb.validation_errors.is_too_large")) if body.bytesize > MAX_BYTES
      errors.add(:byte_size, I18n.t("mcweb.validation_errors.does_not_match_content")) unless byte_size == body.bytesize
      errors.add(:sha256, I18n.t("mcweb.validation_errors.does_not_match_content")) unless sha256 == Digest::SHA256.hexdigest(body)
    end

    def immutable_snapshot_fields
      forbidden = changes_to_save.keys - MUTABLE_AFTER_CREATION
      return if forbidden.empty?

      errors.add(:base, I18n.t("mcweb.validation_errors.evidence_snapshot_fields_are_immutable"))
    end
  end
end
