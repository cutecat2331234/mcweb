# frozen_string_literal: true

module Minecraft
  class CloseStalePlayerSessionsJob < ApplicationJob
    queue_as :maintenance

    def perform
      Minecraft::PlayerSession.active.includes(:server).find_each do |session|
        server = session.server
        next if server.last_heartbeat_at.present? && server.last_heartbeat_at > 3.minutes.ago

        session.close!
      end
    end
  end
end
