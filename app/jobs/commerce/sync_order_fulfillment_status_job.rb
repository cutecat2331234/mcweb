# frozen_string_literal: true

module Commerce
  class SyncOrderFulfillmentStatusJob < ApplicationJob
    queue_as :minecraft

    def perform(order_id)
      order = Commerce::Order.find_by(id: order_id)
      return unless order

      Commerce::SyncOrderFulfillmentStatus.call(order: order)
    end
  end
end
