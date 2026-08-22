# frozen_string_literal: true

module Community
  class ReportOutcomeDelivery < ApplicationRecord
    self.table_name = "forum_report_outcome_deliveries"

    belongs_to :report,
      class_name: "Community::Report",
      foreign_key: :forum_report_id,
      inverse_of: :outcome_delivery
    belongs_to :notification, optional: true

    validates :notification, presence: true, on: :create
    validates :public_outcome_code,
      presence: true,
      inclusion: { in: Community::Report::STAFF_PUBLIC_OUTCOME_CODES }
    validates :idempotency_key_digest,
      presence: true,
      format: { with: /\A[0-9a-f]{64}\z/ }

    attr_readonly :forum_report_id,
      :notification_id,
      :public_outcome_code,
      :idempotency_key_digest,
      :created_at

    before_update :reject_change
    before_destroy :reject_change

    private

    def reject_change
      errors.add(:base, :invalid)
      throw :abort
    end
  end
end
