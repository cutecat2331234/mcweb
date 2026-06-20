# frozen_string_literal: true

module Minecraft
  class ChainFulfillmentAfterStartJob < ApplicationJob
    queue_as :minecraft

    def perform(server_id)
      server = Minecraft::Server.find_by(id: server_id)
      return unless server&.process_running?

      self.class.pending_fulfillments_for(server).find_each do |fulfillment|
        Minecraft::DispatchFulfillmentJob.perform_later(fulfillment.id)
      end
    end

    def self.pending_fulfillments_for(server)
      public_id = server.public_id

      Commerce::Fulfillment
        .joins(:order_item)
        .where(status: "pending")
        .where(
          <<~SQL.squish,
            COALESCE(store_order_items.fulfillment_snapshot->'fulfillment_config'->>'server_id', '') = :public_id
            OR COALESCE(store_order_items.fulfillment_snapshot->'fulfillment_config'->>'minecraft_server_id', '') = :public_id
            OR COALESCE(store_order_items.fulfillment_snapshot->>'server_id', '') = :public_id
            OR COALESCE(store_order_items.fulfillment_snapshot->>'minecraft_server_id', '') = :public_id
          SQL
          public_id: public_id
        )
    end
  end
end
