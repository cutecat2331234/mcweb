# frozen_string_literal: true

module Minecraft
  class DispatchFulfillmentJob < ApplicationJob
    queue_as :minecraft

    def perform(fulfillment_id)
      fulfillment = Commerce::Fulfillment.find(fulfillment_id)
      return if fulfillment.status != "pending"

      if Minecraft::ConnectorTask.where(store_fulfillment: fulfillment, status: %w[pending claimed]).exists?
        return
      end

      order_item = fulfillment.order_item
      snapshot = order_item.fulfillment_snapshot
      server_public_id = snapshot.dig("fulfillment_config", "server_id") || snapshot.dig("fulfillment_config", "minecraft_server_id")

      server =
        if server_public_id.present?
          Minecraft::Server.find_by(public_id: server_public_id.to_s) ||
            Minecraft::Server.find_by(id: server_public_id.to_i)
        end

      unless server
        Rails.logger.error("[DispatchFulfillmentJob] No Minecraft server found for fulfillment #{fulfillment_id} (server_id=#{server_public_id.inspect})")
        return
      end

      existing = Minecraft::ConnectorTask.find_by(store_fulfillment: fulfillment)
      if existing
        existing.update!(status: "pending")
      else
        Minecraft::ConnectorTask.create!(
          server: server,
          store_fulfillment: fulfillment,
          task_type: snapshot.dig("fulfillment_config", "task_type") || "deliver_item",
          delivery_id: fulfillment.delivery_id,
          status: "pending",
          payload: {
            delivery_id: fulfillment.delivery_id,
            order_item_id: order_item.id,
            fulfillment_snapshot: snapshot
          }
        )
      end

      fulfillment.increment!(:attempts_count)
    end
  end
end
