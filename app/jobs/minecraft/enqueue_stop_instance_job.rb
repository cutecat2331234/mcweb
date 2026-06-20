# frozen_string_literal: true

module Minecraft
  class EnqueueStopInstanceJob < ApplicationJob
    queue_as :minecraft

    def perform(server_id, payload: {})
      server = Minecraft::Server.find_by(id: server_id)
      return unless server&.node_managed?

      Minecraft::EnqueueNodeTask.call(
        node: server.node,
        server: server,
        task_type: "stop_instance",
        payload: payload
      )
    end
  end
end
