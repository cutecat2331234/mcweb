# frozen_string_literal: true

module Minecraft
  class EnqueueNodeTask < ApplicationService
    TASK_TYPES = %w[
      start_instance
      stop_instance
      restart_instance
      exec_command
      collect_metrics
      tail_logs
      backup_world
      restore_world
      sync_files
    ].freeze

    def initialize(node:, server: nil, task_type:, payload: {}, delivery_id: nil)
      @node = node
      @server = server
      @task_type = task_type.to_s
      @payload = payload.deep_stringify_keys
      @delivery_id = delivery_id
    end

    def call
      return ServiceResult.failure(error: "Unknown task type.") unless TASK_TYPES.include?(@task_type)
      return ServiceResult.failure(error: "Server is required for this task.") if instance_task? && @server.nil?
      return ServiceResult.failure(error: "Server is not managed by this node.") if @server && @server.minecraft_node_id != @node.id

      if @server && instance_lifecycle_task?
        @server.update!(process_state: lifecycle_state)
      end

      merged_payload = build_payload

      task = Minecraft::NodeTask.create!(
        node: @node,
        server: @server,
        task_type: @task_type,
        delivery_id: @delivery_id || SecureRandom.uuid,
        status: "pending",
        priority: urgent_task? ? "urgent" : "normal",
        payload: merged_payload
      )

      @node.wake_for_tasks! if urgent_task?

      ServiceResult.success(task: task)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def urgent_task?
      Minecraft::NodeTask.urgent_task_type?(@task_type)
    end

    def instance_task?
      %w[start_instance stop_instance restart_instance exec_command tail_logs backup_world restore_world sync_files].include?(@task_type)
    end

    def instance_lifecycle_task?
      %w[start_instance stop_instance restart_instance].include?(@task_type)
    end

    def lifecycle_state
      case @task_type
      when "start_instance" then :starting
      when "stop_instance" then :stopping
      when "restart_instance" then :starting
      else @server.process_state
      end
    end

    def build_payload
      payload = @payload.dup
      return payload unless @server

      payload["process_driver"] ||= @server.process_driver
      payload["process_config"] ||= @server.process_config
      payload["working_directory"] ||= @server.working_directory
      payload["server_id"] ||= @server.public_id
      payload
    end
  end
end
