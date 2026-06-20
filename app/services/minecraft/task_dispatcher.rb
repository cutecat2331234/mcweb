# frozen_string_literal: true

module Minecraft
  class TaskDispatcher < ApplicationService
    STALE_CLAIM_AFTER = 10.minutes
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
        reclaim_stale_claimed_tasks!

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

    def reclaim_stale_claimed_tasks!
      processed_delivery_ids = Minecraft::ProcessedDelivery
        .where(server: @server, status: "completed")
        .select(:delivery_id)

      Minecraft::ConnectorTask
        .where(server: @server, status: "claimed")
        .where("claimed_at IS NULL OR claimed_at < ?", STALE_CLAIM_AFTER.ago)
        .where("delivery_id IS NULL OR delivery_id NOT IN (?)", processed_delivery_ids)
        .update_all(status: "pending", claimed_at: nil, updated_at: Time.current)
    end

    def complete_task
      task = @task || Minecraft::ConnectorTask.find_by(id: @task_id, server: @server)
      return ServiceResult.failure(error: "Task not found.") unless task

      Minecraft::ConnectorTask.transaction do
        task.lock!
        if task.completed? || task.failed?
          return ServiceResult.success(task: task, idempotent: true)
        end

        if delivery_successful?
          task.complete!(@result)
        else
          task.fail!(@result)
        end

        if task.fulfillment
          if delivery_successful?
            task.fulfillment.update!(
              status: "fulfilled",
              fulfilled_at: Time.current,
              last_error: nil
            )
            Commerce::SyncOrderFulfillmentStatusJob.perform_later(task.fulfillment.store_order_id)
          else
            error_message = extract_error_message
            task.fulfillment.mark_failed!(error: error_message)
          end
        end

        if task.delivery_id.present?
          delivery_status = delivery_successful? ? "completed" : "failed"
          record = Minecraft::ProcessedDelivery.find_or_initialize_by(
            server: @server,
            delivery_id: task.delivery_id
          )
          record.status = delivery_status
          record.result = @result
          record.save!
        end
      end

      ServiceResult.success(task: task, idempotent: false)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    def delivery_successful?
      return false if @result.blank?

      value = @result
      value = value.with_indifferent_access if value.respond_to?(:with_indifferent_access)
      return false if value[:success] == false || value["success"] == false
      return false if value[:status].to_s == "failed" || value["status"].to_s == "failed"

      true
    end

    def extract_error_message
      value = @result
      value = value.with_indifferent_access if value.respond_to?(:with_indifferent_access)
      value[:error] || value["error"] || value[:message] || value["message"] || "Delivery failed"
    end
  end
end
