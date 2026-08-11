# frozen_string_literal: true

module Operations
  class RunManualTaskJob < ApplicationJob
    queue_as :maintenance

    def perform(run_id)
      run = Operations::ManualTaskRun.find(run_id)
      return if run.succeeded? || run.failed?

      run.with_lock do
        return if run.succeeded? || run.failed?

        if run.running?
          # Active Job keeps its job_id when the adapter retries the same
          # serialized delivery. Allow that delivery to resume after a worker
          # crash, while rejecting an unrelated duplicate job for this run.
          return if run.job_id.present? && run.job_id != job_id
        else
          run.update!(
            status: "running",
            job_id: run.job_id.presence || job_id,
            started_at: Time.current
          )
        end
      end

      result = Operations::ManualTaskCatalog.execute(run)
      run.update!(
        status: "succeeded",
        result: result,
        error_code: nil,
        error_message: nil,
        finished_at: Time.current
      )
      audit(run, "operations.manual_task.succeeded")
    rescue Operations::ManualTaskCatalog::InvalidTask,
           Operations::ManualTaskCatalog::ExecutionError => error
      mark_failed(
        run,
        error.respond_to?(:code) ? error.code : error.message,
        error.message,
        result: error.respond_to?(:result) ? error.result : {}
      )
    rescue StandardError => error
      Rails.logger.error(
        "[operations.manual_task] run=#{run_id} failed=#{error.class} message=#{error.message}"
      )
      mark_failed(run, "manual_task_execution_failed", error.class.name)
    end

    private

    def mark_failed(run, code, message, result: {})
      return unless run&.persisted?

      run.update!(
        status: "failed",
        error_code: code.to_s.first(120),
        error_message: message.to_s.first(2_000),
        result: result.to_h,
        finished_at: Time.current
      )
      audit(run, "operations.manual_task.failed", error_code: run.error_code)
    end

    def audit(run, action, metadata = {})
      Administration::AuditLogger.call(
        actor: run.requested_by,
        action:,
        resource: run,
        metadata: {
          task_key: run.task_key,
          manual_task_run_id: run.id,
          **metadata
        }
      )
    end
  end
end
