# frozen_string_literal: true

module Community
  class ReportAttachment < ApplicationRecord
    self.table_name = "forum_report_attachments"

    belongs_to :report,
      class_name: "Community::Report",
      foreign_key: :forum_report_id,
      inverse_of: :evidence_links
    belongs_to :attachment,
      class_name: "SecureEvidence::Attachment",
      foreign_key: :secure_evidence_attachment_id
    belongs_to :sealed_by, class_name: "User"

    attr_readonly :forum_report_id,
      :secure_evidence_attachment_id,
      :sealed_by_id,
      :created_at

    before_update :prevent_change
    before_destroy :prevent_change

    private

    def prevent_change
      errors.add(:base, :immutable)
      throw(:abort)
    end
  end
end
