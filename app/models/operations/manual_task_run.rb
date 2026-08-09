# frozen_string_literal: true

module Operations
  class ManualTaskRun < ApplicationRecord
    self.table_name = "operations_manual_task_runs"

    belongs_to :requested_by, class_name: "User", optional: true

    enum :status,
         {
           queued: "queued",
           running: "running",
           succeeded: "succeeded",
           failed: "failed"
         },
         validate: true

    validates :task_key, presence: true, length: { maximum: 120 }
    validates :idempotency_key,
              presence: true,
              length: { maximum: 160 },
              uniqueness: { scope: :task_key }
    validates :job_id, length: { maximum: 160 }, allow_nil: true
    validates :error_code, length: { maximum: 120 }, allow_nil: true
    validates :requested_at, presence: true

    scope :recent_first, -> { order(requested_at: :desc, id: :desc) }
  end
end
