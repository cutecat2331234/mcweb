# frozen_string_literal: true

module Operations
  module DurableEnqueueManualTasks
    module_function

    PERMISSIONS = %w[system.jobs.manage].freeze

    def register(registry)
      registry.register(
        key: "operations.durable_enqueue.recover_due",
        label_key: "admin.jobsPage.manualTasks.tasks.recoverDurableEnqueue.title",
        description_key: "admin.jobsPage.manualTasks.tasks.recoverDurableEnqueue.description",
        permissions: PERMISSIONS
      ) do |_run|
        unwrap!(Operations::RecoverDurableEnqueue.call(trigger: "manual"))
      end

      registry.register(
        key: "operations.durable_enqueue.retry_selected",
        label_key: "admin.jobsPage.manualTasks.tasks.retryDurableEnqueue.title",
        description_key: "admin.jobsPage.manualTasks.tasks.retryDurableEnqueue.description",
        permissions: PERMISSIONS,
        argument_schema: {
          "intent_public_ids" => {
            type: "uuid_list",
            required: true,
            maximum_items: 200,
            label_key: "admin.jobsPage.manualTasks.durableIntentIds",
            help_key: "admin.jobsPage.manualTasks.durableIntentIdsHelp"
          },
          "reason" => {
            type: "string",
            required: true,
            maximum: 500,
            label_key: "admin.jobsPage.manualTasks.retryReason",
            help_key: "admin.jobsPage.manualTasks.retryReasonHelp"
          }
        }
      ) do |run|
        unwrap!(
          Operations::RecoverDurableEnqueue.call(
            intent_public_ids: run.arguments.fetch("intent_public_ids"),
            trigger: "manual",
            actor: run.requested_by,
            reopen: true,
            reason: run.arguments.fetch("reason")
          )
        )
      end
    end

    def unwrap!(result)
      unless result.success?
        raise Operations::ManualTaskCatalog::ExecutionError.new(
          result.code.presence || "durable_enqueue_recovery_failed",
          result: result.value.to_h.slice(
            :scanned_count,
            :candidate_count,
            :enqueued_count,
            :failed_count,
            :skipped_count,
            :partial,
            :intent_public_ids
          )
        )
      end

      result.value
    end
    private_class_method :unwrap!
  end
end
