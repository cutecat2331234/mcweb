# frozen_string_literal: true

module Minecraft
  class ManagePlayerSessions < ApplicationService
    def initialize(server:, player_profile:, username:, event:)
      @server = server
      @player_profile = player_profile
      @username = username
      @event = event.to_s
    end

    def call
      if join_event?
        close_other_active_sessions!
        Minecraft::PlayerSession.create!(
          player_profile: @player_profile,
          server: @server,
          username: @username,
          joined_at: Time.current,
          source: "connector"
        )
      elsif quit_event?
        active_session&.close!
      end

      ServiceResult.success
    end

    private

    def join_event?
      @event.in?(%w[player.join player.first_join join])
    end

    def quit_event?
      @event.in?(%w[player.quit quit leave])
    end

    def active_session
      Minecraft::PlayerSession.active.find_by(
        player_profile: @player_profile,
        minecraft_server_id: @server.id
      )
    end

    def close_other_active_sessions!
      Minecraft::PlayerSession.active
        .for_server(@server)
        .where(player_profile: @player_profile)
        .find_each(&:close!)
    end
  end
end
