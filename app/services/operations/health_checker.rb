# frozen_string_literal: true

module Operations
  class HealthChecker < ApplicationService
    def call
      checks = {
        database: check_database,
        queue: check_queue,
        storage: check_storage
      }

      healthy = checks.values.all? { |check| check[:status] == "ok" }
      ServiceResult.success(status: healthy ? "ok" : "degraded", checks: checks)
    end

    private

    def check_database
      ActiveRecord::Base.connection.execute("SELECT 1")
      { status: "ok" }
    rescue StandardError => e
      { status: "error", message: e.message }
    end

    def check_queue
      pending = SolidQueue::Job.where(finished_at: nil).count
      failed = SolidQueue::FailedExecution.count
      { status: "ok", pending_jobs: pending, failed_jobs: failed }
    rescue StandardError => e
      { status: "error", message: e.message }
    end

    def check_storage
      ActiveStorage::Blob.limit(1).pick(:id)
      { status: "ok" }
    rescue StandardError => e
      { status: "error", message: e.message }
    end
  end
end
