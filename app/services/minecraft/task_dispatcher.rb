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
        ServiceResult.failure(
          error: I18n.t("mcweb.user_copy.unknown_task_action", action: @action)
        )
      end
    end

    private

    def claim_tasks
      return simulate_claimable_tasks if developer_mode_simulation?

      tasks = []
      Minecraft::ConnectorTask.transaction do
        reclaim_stale_claimed_tasks!

        pending = Minecraft::ConnectorTask
          .lock
          .where(server: @server, status: "pending")
          .order(:created_at, :id)
          .limit(100)
          .to_a
        claimed_ordering_keys = Minecraft::ConnectorTask
          .where(server: @server, status: "claimed")
          .pluck(:payload)
          .each_with_object({}) do |payload, keys|
            key = payload.to_h["ordering_key"].to_s.presence
            keys[key] = true if key
          end

        pending.each do |task|
          break if tasks.size >= 10

          ordering_key = task.payload.to_h["ordering_key"].to_s.presence
          next if ordering_key && claimed_ordering_keys[ordering_key]

          task.update!(status: "claimed", claimed_at: Time.current)
          tasks << task
          claimed_ordering_keys[ordering_key] = true if ordering_key
        end
      end

      ServiceResult.success(tasks: tasks)
    end

    def simulate_claimable_tasks
      simulated = 0
      Minecraft::ConnectorTask
        .where(server: @server, status: "pending")
        .order(:created_at)
        .limit(10)
        .find_each do |task|
          result = self.class.call(
            server: @server,
            task: task,
            result: {
              success: true,
              status: "completed",
              simulated: true,
              developer_mode: true
            },
            action: :complete
          )
          simulated += 1 if result.success?
        end

      ServiceResult.success(tasks: [], simulated: simulated)
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
      return ServiceResult.failure(error: :task_not_found) unless task

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
            task.fulfillment.mark_fulfilled!(
              result: {
                success: true,
                status: normalized_result_value(:status) || "completed",
                simulated: normalized_result_value(:simulated),
                external_reference: task.delivery_id
              }
            )
            Commerce::SyncOrderFulfillmentStatusJob.perform_later(task.fulfillment.store_order_id)
          else
            error_code = extract_error_code
            task.fulfillment.mark_failed!(
              error: error_code,
              result: {
                success: false,
                status: normalized_result_value(:status) || "failed",
                error_code: error_code,
                external_reference: task.delivery_id
              }
            )
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

    def extract_error_code
      Commerce::Fulfillment.normalize_error_code(
        normalized_result_value(:error_code) ||
          normalized_result_value(:code) ||
          normalized_result_value(:error) ||
          normalized_result_value(:status) ||
          "delivery_failed"
      )
    end

    def normalized_result_value(key)
      value = @result
      value = value.with_indifferent_access if value.respond_to?(:with_indifferent_access)
      value[key]
    end

    def developer_mode_simulation?
      Mcweb::DeveloperMode.enabled? &&
        Mcweb::DeveloperMode.integration(:minecraft_nodes) == :simulate
    end
  end
end
