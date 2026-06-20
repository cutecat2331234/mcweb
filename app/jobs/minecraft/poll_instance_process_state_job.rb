# frozen_string_literal: true

module Minecraft
  class PollInstanceProcessStateJob < ApplicationJob
    queue_as :minecraft

    MAX_ATTEMPTS = 20
    INTERVAL = 3.seconds

    def perform(server_id, attempt = 0)
      server = Minecraft::Server.find_by(id: server_id)
      return unless server

      if server.process_running?
        Minecraft::ChainFulfillmentAfterStartJob.perform_later(server_id)
      elsif attempt < MAX_ATTEMPTS && server.process_state.in?(%w[starting stopping])
        self.class.set(wait: INTERVAL).perform_later(server_id, attempt + 1)
      end
    end
  end
end
