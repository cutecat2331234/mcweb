# frozen_string_literal: true

module Community
  class ReportEvidence < ApplicationRecord
    self.table_name = "forum_report_evidences"

    has_encrypted :snapshot, type: :json, encrypted_attribute: :encrypted_snapshot

    belongs_to :report,
      class_name: "Community::Report",
      foreign_key: :forum_report_id,
      inverse_of: :evidence

    validates :subject_type, :subject_id, :captured_at, presence: true
    validates :subject_revision, numericality: { only_integer: true, greater_than: 0 }
    validates :content_digest, format: { with: /\A[0-9a-f]{64}\z/ }
    validate :snapshot_must_be_mapping

    before_update :prevent_mutation
    before_destroy :prevent_mutation

    def digest_valid?
      ActiveSupport::SecurityUtils.secure_compare(
        content_digest,
        Digest::SHA256.hexdigest(JSON.generate(snapshot))
      )
    end

    private

    def snapshot_must_be_mapping
      errors.add(:snapshot, :invalid) unless snapshot.is_a?(Hash)
    end

    def prevent_mutation
      errors.add(:base, :immutable)
      throw(:abort)
    end
  end
end
