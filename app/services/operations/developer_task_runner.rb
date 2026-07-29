# frozen_string_literal: true

module Operations
  class DeveloperTaskRunner < ApplicationService
    TASKS = {
      "scan_attachments" => "Maintenance::ScanForumAttachmentsJob",
      "cleanup_uploads" => "Maintenance::CleanupForumUploadsJob",
      "expire_orders" => "Commerce::ExpirePendingOrdersJob",
      "recover_payment_webhooks" => "Payments::RecoverWebhookEventsJob",
      "publish_scheduled_topics" => "Community::PublishScheduledTopicsJob",
      "recover_fulfillments" => "Commerce::RecoverFulfillmentsJob",
      "cleanup_sessions" => "Maintenance::CleanupExpiredSessionsJob"
    }.freeze

    def initialize(task:, actor:)
      @task = task.to_s
      @actor = actor
    end

    def call
      return unavailable unless Mcweb::DeveloperMode.enabled?

      class_name = TASKS[@task]
      return invalid_task unless class_name

      Administration::AuditLogger.call(
        actor: @actor,
        action: "developer_mode.task_trigger_requested",
        metadata: { task: @task }
      )
      job = class_name.constantize.perform_later
      Administration::AuditLogger.call(
        actor: @actor,
        action: "developer_mode.task_triggered",
        metadata: {
          task: @task,
          job_id: job.job_id
        }
      )
      ServiceResult.success(job)
    rescue NameError => error
      ServiceResult.failure(
        error: "developer_task_unavailable",
        code: error.class.name
      )
    end

    private

    def unavailable
      ServiceResult.failure(
        error: "developer_mode_not_enabled",
        code: "developer_mode_not_enabled"
      )
    end

    def invalid_task
      ServiceResult.failure(
        error: "developer_task_invalid",
        code: "developer_task_invalid"
      )
    end
  end
end
