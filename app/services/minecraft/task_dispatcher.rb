# frozen_string_literal: true

module Minecraft
  class TaskDispatcher < ApplicationService
    def initialize(server:, task: nil, task_id: nil, result: {}, action: :claim)
      @server = server
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
      Minecraft::ConnectorTask.transaction do
        pending = Minecraft::ConnectorTask
          .lock
          .where(server: @server, status: "pending")
          .order(:created_at)
          .limit(10)

        pending.each do |task|
          task.update!(status: "claimed", claimed_at: Time.current)
          tasks << task
        end
      end

      ServiceResult.success(tasks: tasks)
    end

    def complete_task
      task = @task || Minecraft::ConnectorTask.find_by(id: @task_id, server: @server)
      return ServiceResult.failure(error: "Task not found.") unless task

      Minecraft::ConnectorTask.transaction do
        task.lock!
        return ServiceResult.success(task: task, idempotent: true) if task.status == "completed"

        task.update!(
          status: "completed",
          result: @result,
          completed_at: Time.current
        )

        if task.store_fulfillment
          task.store_fulfillment.update!(
            status: "fulfilled",
            fulfilled_at: Time.current,
            last_error: nil
          )
        end

        if task.delivery_id.present?
          Minecraft::ProcessedDelivery.find_or_create_by!(
            server: @server,
            delivery_id: task.delivery_id
          ) do |record|
            record.status = "completed"
            record.result = @result
          end
        end
      end

      ServiceResult.success(task: task, idempotent: false)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
