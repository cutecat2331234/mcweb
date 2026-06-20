# frozen_string_literal: true

module Minecraft
  class DispatchFulfillmentJob < ApplicationJob
    queue_as :minecraft

    def perform(fulfillment_id)
      fulfillment = Commerce::Fulfillment.find(fulfillment_id)
      return if fulfillment.status != "pending"

      order = fulfillment.order
      return if order.refunded? || order.cancelled?

      existing = Minecraft::ConnectorTask.find_by(fulfillment: fulfillment)
      if existing&.completed?
        reconcile_completed_fulfillment!(fulfillment)
        return
      end

      if Minecraft::ConnectorTask.where(fulfillment: fulfillment, status: %w[pending claimed]).exists?
        return
      end

      order_item = fulfillment.order_item
      snapshot = order_item.fulfillment_snapshot || {}
      config = snapshot["fulfillment_config"] || snapshot[:fulfillment_config] || {}
      server_public_id = config["server_id"] || config[:server_id] || config["minecraft_server_id"] || config[:minecraft_server_id]

      server =
        if server_public_id.present?
          Minecraft::Server.find_by(public_id: server_public_id.to_s) ||
            Minecraft::Server.find_by(id: server_public_id.to_i)
        end

      unless server
        Rails.logger.error("[DispatchFulfillmentJob] No Minecraft server found for fulfillment #{fulfillment_id} (server_id=#{server_public_id.inspect})")
        fulfillment.mark_failed!(error: "server_not_found")
        return
      end

      if maintenance_blocks_fulfillment?(server)
        Rails.logger.info("[DispatchFulfillmentJob] Deferred fulfillment #{fulfillment_id} — server in maintenance")
        Minecraft::DispatchFulfillmentJob.set(wait: 10.minutes).perform_later(fulfillment_id)
        return
      end

      payload_result = Commerce::BuildConnectorTaskPayload.call(fulfillment: fulfillment)
      unless payload_result.success?
        fulfillment.mark_failed!(error: payload_result.error)
        return
      end

      task_payload = payload_result.value
      task_type = config["task_type"] || config[:task_type] || "deliver_item"

      if existing
        unless existing.failed?
          return
        end

        existing.update!(
          server: server,
          status: "pending",
          claimed_at: nil,
          completed_at: nil,
          result: {},
          payload: task_payload,
          task_type: task_type
        )
      else
        begin
          Minecraft::ConnectorTask.create!(
            server: server,
            fulfillment: fulfillment,
            task_type: task_type,
            delivery_id: fulfillment.delivery_id,
            status: "pending",
            payload: task_payload
          )
        rescue ActiveRecord::RecordNotUnique
          existing = Minecraft::ConnectorTask.find_by(fulfillment: fulfillment)
          return if existing.nil? || existing.completed? || existing.pending? || existing.claimed?

          unless existing.failed?
            return
          end

          existing.update!(
            server: server,
            status: "pending",
            claimed_at: nil,
            completed_at: nil,
            result: {},
            payload: task_payload,
            task_type: task_type
          )
        end
      end

      fulfillment.increment!(:attempts_count)
    end

    private

    def reconcile_completed_fulfillment!(fulfillment)
      return if fulfillment.fulfilled?

      fulfillment.mark_fulfilled!
      Commerce::SyncOrderFulfillmentStatusJob.perform_later(fulfillment.store_order_id)
    end

    def maintenance_blocks_fulfillment?(server)
      return false unless Minecraft::MaintenanceActive.pause_fulfillment?

      Minecraft::MaintenanceActive.call(server: server).value[:active]
    end
  end
end
