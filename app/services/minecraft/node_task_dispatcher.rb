# frozen_string_literal: true

module Minecraft
  class NodeTaskDispatcher < ApplicationService
    STALE_CLAIM_AFTER = 10.minutes

    def initialize(node:, task: nil, task_id: nil, result: {}, action: :claim)
      @node = node
      @task = task
      @task_id = task_id
      @result = result
      @action = action
    end

    def call
      case @action
      when :claim then claim_tasks
      when :complete then complete_task
      else
        ServiceResult.failure(error: "Unknown task action: #{@action}")
      end
    end

    private

    def claim_tasks
      tasks = []
      Minecraft::NodeTask.transaction do
        reclaim_stale_claimed_tasks!

        pending = @node.node_tasks.claimable.lock.limit(10)

        pending.each do |task|
          task.update!(status: "claimed", claimed_at: Time.current)
          tasks << task
        end
      end

      ServiceResult.success(tasks: tasks)
    end

    def reclaim_stale_claimed_tasks!
      Minecraft::NodeTask
        .where(node: @node, status: "claimed")
        .where("claimed_at IS NULL OR claimed_at < ?", STALE_CLAIM_AFTER.ago)
        .update_all(status: "pending", claimed_at: nil, updated_at: Time.current)
    end

    def complete_task
      task = @task || Minecraft::NodeTask.find_by(id: @task_id, node: @node)
      return ServiceResult.failure(error: "Task not found.") unless task

      Minecraft::NodeTask.transaction do
        task.lock!
        if task.completed? || task.failed?
          return ServiceResult.success(task: task, idempotent: true)
        end

        if delivery_successful?
          task.complete!(@result)
        else
          task.fail!(@result)
        end

        if task.server
          sync_server_process_state!(task)
        end
      end

      Minecraft::ProcessNodeTaskCompletionJob.perform_later(task.id)

      ServiceResult.success(task: task, idempotent: false)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    def sync_server_process_state!(task)
      server = task.server
      return unless server

      case task.task_type
      when "start_instance"
        server.update!(process_state: delivery_successful? ? :running : :error)
      when "stop_instance"
        server.update!(process_state: delivery_successful? ? :stopped : :error)
      when "restart_instance"
        server.update!(process_state: delivery_successful? ? :running : :error)
      when "collect_metrics"
        sync_metrics!(server) if delivery_successful?
      end
    end

    def sync_metrics!(server)
      value = normalize_result
      metrics = value[:metrics] || value["metrics"]
      return if metrics.blank?

      metadata = server.metadata.merge(
        "last_metrics" => metrics,
        "last_metrics_at" => Time.current.iso8601
      )
      server.update!(metadata: metadata)

      process_state = value[:process_state] || value["process_state"]
      server.update!(process_state: process_state) if process_state.present?
    end

    def normalize_result
      value = @result
      value.respond_to?(:with_indifferent_access) ? value.with_indifferent_access : value
    end

    def delivery_successful?
      return false if @result.blank?

      value = @result
      value = value.with_indifferent_access if value.respond_to?(:with_indifferent_access)
      return false if value[:success] == false || value["success"] == false
      return false if value[:status].to_s == "failed" || value["status"].to_s == "failed"

      true
    end
  end
end
