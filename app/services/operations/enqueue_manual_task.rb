# frozen_string_literal: true

module Operations
  class EnqueueManualTask < ApplicationService
    def initialize(task_key:, actor:, arguments:, idempotency_key:, audit_context: {})
      @task_key = task_key.to_s
      @actor = actor
      @arguments = arguments
      @idempotency_key = idempotency_key.to_s.first(160)
      @audit_context = audit_context.to_h.symbolize_keys
    end

    def call
      entry = Operations::ManualTaskCatalog.entry(@task_key)
      return failure("manual_task_unknown") unless entry
      return failure("manual_task_forbidden") unless Operations::ManualTaskCatalog.allowed?(@actor, entry)
      return failure("manual_task_idempotency_required") if @idempotency_key.blank?

      normalized_arguments = Operations::ManualTaskCatalog.normalize_arguments(entry, @arguments)
      run, created = find_or_create_run(normalized_arguments)
      return ServiceResult.success(run: run, replayed: true) unless created

      job = Operations::RunManualTaskJob.perform_later(run.id)
      run.update!(job_id: job.job_id)
      audit("operations.manual_task.requested", run)
      ServiceResult.success(run: run, replayed: false)
    rescue Operations::ManualTaskCatalog::InvalidTask => error
      failure(error.message)
    rescue ActiveRecord::RecordNotUnique
      run = Operations::ManualTaskRun.find_by!(
        task_key: @task_key,
        idempotency_key: @idempotency_key
      )
      ServiceResult.success(run: run, replayed: true)
    rescue StandardError => error
      if defined?(run) && run&.persisted? && !run.finished_at?
        run.update_columns(
          status: "failed",
          error_code: "manual_task_enqueue_failed",
          error_message: error.class.name,
          finished_at: Time.current,
          updated_at: Time.current
        )
        audit("operations.manual_task.enqueue_failed", run, error_code: "manual_task_enqueue_failed")
      end
      failure("manual_task_enqueue_failed")
    end

    private

    def find_or_create_run(arguments)
      existing = Operations::ManualTaskRun.find_by(
        task_key: @task_key,
        idempotency_key: @idempotency_key
      )
      return [ existing, false ] if existing

      [
        Operations::ManualTaskRun.create!(
          task_key: @task_key,
          requested_by: @actor,
          arguments:,
          idempotency_key: @idempotency_key,
          requested_at: Time.current
        ),
        true
      ]
    end

    def audit(action, run, metadata = {})
      Administration::AuditLogger.call(
        actor: @actor,
        action:,
        resource: run,
        metadata: {
          task_key: @task_key,
          manual_task_run_id: run.id,
          **metadata
        },
        ip_address: @audit_context[:ip_address],
        user_agent: @audit_context[:user_agent],
        request_id: @audit_context[:request_id]
      )
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
