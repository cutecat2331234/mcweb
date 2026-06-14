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
      server_id = snapshot.dig("fulfillment_config", "server_id") || snapshot.dig("fulfillment_config", "minecraft_server_id")
      server = Minecraft::Server.find_by(id: server_id) || Minecraft::Server.first
      return unless server

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

      fulfillment.increment!(:attempts_count)
    end
  end
end
