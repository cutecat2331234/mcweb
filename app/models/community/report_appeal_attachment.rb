# frozen_string_literal: true

module Community
  class ReportAppealAttachment < ApplicationRecord
    self.table_name = "forum_report_appeal_attachments"

    belongs_to :appeal,
      class_name: "Community::ReportAppeal",
      foreign_key: :forum_report_appeal_id,
      inverse_of: :evidence_links
    belongs_to :attachment,
      class_name: "SecureEvidence::Attachment",
      foreign_key: :secure_evidence_attachment_id
    belongs_to :sealed_by, class_name: "User"

    enum :audience, { appellant: "appellant", reviewers: "reviewers" }, prefix: true

    attr_readonly :forum_report_appeal_id,
      :secure_evidence_attachment_id,
      :sealed_by_id,
      :audience,
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
