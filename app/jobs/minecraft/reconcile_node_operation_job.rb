# frozen_string_literal: true

module Minecraft
  class ReconcileNodeOperationJob < ApplicationJob
    queue_as :minecraft
    class WorldOperationReconciliationError < StandardError; end

    def perform(operation_id)
      operation = Minecraft::NodeOperation.find(operation_id)
      apply_target_results(operation)
      start_next_operation = false

      operation.with_lock do
        batches = operation.batches.reload
        completed_targets = batches.sum(:completed_target_count)
        failed_targets = batches.sum(:failed_target_count) + unreported_failed_targets(batches)
        terminal_batches = batches.terminal.count
        all_terminal = batches.exists? && terminal_batches == batches.count

        attributes = {
          completed_target_count: completed_targets,
          failed_target_count: failed_targets,
          result: {
            "batch_count" => batches.count,
            "terminal_batch_count" => terminal_batches,
            "completed_target_count" => completed_targets,
            "failed_target_count" => failed_targets
          }
        }

        if all_terminal && !operation.terminal?
          attributes[:status] = failed_targets.zero? ? "completed" : "completed_with_errors"
          attributes[:completed_at] = Time.current
          attributes[:dispatch_slot] = nil
          start_next_operation = true
        elsif !operation.terminal?
          attributes[:status] = "running"
        end

        operation.update!(attributes)
      end

      if operation.terminal?
        reconcile_world_operation!(operation: operation, action: :terminal)
      end

      wake_nodes_with_pending_batches(operation)
      Minecraft::PrepareNodeOperationJob.perform_later if start_next_operation
    end

    private

    def unreported_failed_targets(batches)
      batches.where(status: %w[failed cancelled]).sum(
        "target_count - completed_target_count - failed_target_count"
      )
    end

    def apply_target_results(operation)
      operation.target_results.where(applied_at: nil).find_each do |target_result|
        target_result.with_lock do
          next if target_result.applied_at?

          apply_collect_metrics(target_result) if operation.operation_type == "collect_metrics"
          if Minecraft::ReconcileWorldOperation::WORLD_OPERATION_TYPES.include?(operation.operation_type)
            reconcile_world_operation!(
              operation: operation,
              action: :target_result,
              target_result: target_result
            )
          end
          target_result.update!(applied_at: Time.current)
        end
      end
    end

    def apply_collect_metrics(target_result)
      return unless target_result.status_completed? && target_result.server

      value = target_result.result.with_indifferent_access
      metrics = value[:metrics]
      return if metrics.blank?

      server = target_result.server
      metadata = server.metadata.merge(
        "last_metrics" => metrics,
        "last_metrics_at" => Time.current.iso8601
      )
      attributes = { metadata: metadata }
      process_state = value[:process_state].to_s
      attributes[:process_state] = process_state if Minecraft::Server.process_states.key?(process_state)
      server.update!(attributes)
    end

    def wake_nodes_with_pending_batches(operation)
      Minecraft::Node
        .joins(:operation_batches)
        .where(minecraft_node_operation_batches: { status: "ready" })
        .where(id: operation.batches.select(:minecraft_node_id))
        .distinct
        .find_each(&:wake_for_tasks!)
    end

    def reconcile_world_operation!(**attributes)
      result = Minecraft::ReconcileWorldOperation.call(**attributes)
      return result if result.success?

      raise WorldOperationReconciliationError,
        (result.code.presence || "world_operation_reconciliation_failed")
    end
  end
end
