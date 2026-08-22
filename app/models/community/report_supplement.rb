# frozen_string_literal: true

module Community
  class ReportSupplement < ApplicationRecord
    self.table_name = "forum_report_supplements"

    MAX_BODY_LENGTH = 2_000

    belongs_to :report,
      class_name: "Community::Report",
      foreign_key: :forum_report_id,
      inverse_of: :supplements
    belongs_to :reporter, class_name: "User"

    validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }
    validates :idempotency_key_digest,
      presence: true,
      format: { with: /\A[0-9a-f]{64}\z/ }
    validate :reporter_owns_report, on: :create
    validate :report_is_pending, on: :create

    attr_readonly :forum_report_id, :reporter_id, :body, :idempotency_key_digest, :created_at

    before_update :reject_change
    before_destroy :reject_change

    private

    def reject_change
      errors.add(:base, :invalid)
      throw :abort
    end

    def reporter_owns_report
      return if report && reporter_id == report.reporter_id

      errors.add(:reporter_id, :invalid)
    end

    def report_is_pending
      return if report&.pending?

      errors.add(:forum_report_id, :invalid)
    end
  end
end
