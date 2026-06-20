# frozen_string_literal: true

module Minecraft
  class MarkStaleServersOfflineJob < ApplicationJob
    queue_as :maintenance

    STALE_AFTER = 3.minutes

    def perform
      Minecraft::Server
        .where(status: :online)
        .where("last_heartbeat_at IS NULL OR last_heartbeat_at < ?", STALE_AFTER.ago)
        .find_each { |server| server.update!(status: :offline) }
    end
  end
end
