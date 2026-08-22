# frozen_string_literal: true

module Community
  class ReportDecisionBatch < ApplicationRecord
    self.table_name = "forum_report_decision_batches"

    belongs_to :reviewer, class_name: "User"

    validates :idempotency_key_digest, :request_fingerprint,
      presence: true,
      format: { with: /\A[0-9a-f]{64}\z/ }
    validates :reportable_type, presence: true
    validates :reportable_id, numericality: { only_integer: true, greater_than: 0 }
    validates :desired_status, inclusion: { in: Community::Report::STAFF_FINAL_STATUSES }
    validates :decided_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :result_shape

    attr_readonly :idempotency_key_digest,
      :request_fingerprint,
      :reviewer_id,
      :reportable_type,
      :reportable_id,
      :desired_status,
      :report_ids,
      :decided_count,
      :created_at

    before_update :reject_change
    before_destroy :reject_change

    private

    def result_shape
      normalized_ids = Array(report_ids)
      valid_ids = normalized_ids.all? { |id| id.is_a?(Integer) && id.positive? }
      return if valid_ids && normalized_ids.uniq == normalized_ids && decided_count == normalized_ids.length

      errors.add(:report_ids, :invalid)
    end

    def reject_change
      errors.add(:base, :invalid)
      throw :abort
    end
  end
end
