# frozen_string_literal: true

module Community
  class ReportAppealEvent < ApplicationRecord
    self.table_name = "forum_report_appeal_events"

    EVENT_TYPES = %w[drafted submitted review_started upheld overturned cancelled].freeze

    belongs_to :appeal,
      class_name: "Community::ReportAppeal",
      foreign_key: :forum_report_appeal_id,
      inverse_of: :events
    belongs_to :actor, class_name: "User", optional: true

    validates :event_type, inclusion: { in: EVENT_TYPES }
    validates :to_status, inclusion: { in: ReportAppeal::STATUSES }
    validates :from_status, inclusion: { in: ReportAppeal::STATUSES }, allow_nil: true
    validates :public_outcome_code,
      inclusion: { in: ReportAppeal::PUBLIC_OUTCOME_CODES },
      allow_nil: true
    validates :idempotency_key_digest,
      :request_fingerprint,
      presence: true,
      format: { with: /\A[0-9a-f]{64}\z/ }
    validates :occurred_at, presence: true

    attr_readonly :forum_report_appeal_id,
      :actor_id,
      :event_type,
      :from_status,
      :to_status,
      :public_outcome_code,
      :idempotency_key_digest,
      :request_fingerprint,
      :occurred_at,
      :created_at

    before_update :prevent_change
    before_destroy :prevent_change

    scope :timeline, -> { order(:occurred_at, :id) }

    private

    def prevent_change
      errors.add(:base, :immutable)
      throw(:abort)
    end
  end
end
