# frozen_string_literal: true

module Operations
  class WorkerHeartbeat < ApplicationRecord
    self.table_name = "operations_worker_heartbeats"

    FRESH_FOR = 2.minutes
    RETAIN_FOR = 7.days

    validates :process_ref,
              presence: true,
              length: { is: 64 },
              format: { with: /\A[0-9a-f]{64}\z/ },
              uniqueness: true
    validates :process_kind, inclusion: { in: %w[sidekiq] }
    validates :started_at, :last_seen_at, presence: true

    scope :sidekiq, -> { where(process_kind: "sidekiq") }
    scope :fresh, ->(at = Time.current) {
      where("last_seen_at >= ?", at - FRESH_FOR)
    }
  end
end
