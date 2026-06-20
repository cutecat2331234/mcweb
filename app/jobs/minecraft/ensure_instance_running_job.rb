# frozen_string_literal: true

module Minecraft
  class EnsureInstanceRunningJob < ApplicationJob
    queue_as :minecraft

    def perform(fulfillment_id)
      fulfillment = Commerce::Fulfillment.find_by(id: fulfillment_id)
      return unless fulfillment&.pending?

      server = resolve_server(fulfillment)
      if server && maintenance_blocks_fulfillment?(server)
        Rails.logger.info("[EnsureInstanceRunningJob] Deferred — server #{server.public_id} in maintenance")
        Minecraft::EnsureInstanceRunningJob.set(wait: 10.minutes).perform_later(fulfillment_id)
        return
      end

      return dispatch(fulfillment_id) unless server
      return dispatch(fulfillment_id) unless server.node_managed?
      return dispatch(fulfillment_id) if server.process_running?

      if server.process_state_starting?
        Minecraft::PollInstanceProcessStateJob.set(wait: 5.seconds).perform_later(server.id)
        return
      end

      result = Minecraft::EnqueueNodeTask.call(
        node: server.node,
        server: server,
        task_type: "start_instance",
        delivery_id: "warmup-#{fulfillment.delivery_id}"
      )

      dispatch(fulfillment_id) if result.failure?
    end

    private

    def dispatch(fulfillment_id)
      Minecraft::DispatchFulfillmentJob.perform_later(fulfillment_id)
    end

    def resolve_server(fulfillment)
      snapshot = fulfillment.order_item.fulfillment_snapshot || {}
      config = snapshot["fulfillment_config"] || snapshot[:fulfillment_config] || {}
      server_public_id = config["server_id"] || config[:server_id] || config["minecraft_server_id"] || config[:minecraft_server_id]
      return nil if server_public_id.blank?

      Minecraft::Server.find_by(public_id: server_public_id.to_s)
    end

    def maintenance_blocks_fulfillment?(server)
      return false unless Minecraft::MaintenanceActive.pause_fulfillment?

      Minecraft::MaintenanceActive.call(server: server).value[:active]
    end
  end
end
