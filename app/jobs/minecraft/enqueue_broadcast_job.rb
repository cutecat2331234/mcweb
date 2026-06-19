# frozen_string_literal: true

module Minecraft
  class EnqueueBroadcastJob < ApplicationJob
    queue_as :minecraft

    def perform(message, title: nil, server_id: nil, delivery_id: nil)
      server = server_id.present? ? Minecraft::Server.find_by(public_id: server_id.to_s) : nil
      EnqueueBroadcast.call(
        message: message,
        title: title,
        server: server,
        delivery_id: delivery_id
      )
    end
  end
end
