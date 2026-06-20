# frozen_string_literal: true

module Minecraft
  class IngameStatusForUser < ApplicationService
    def initialize(user:)
      @user = user
    end

    def call
      profile = @user.minecraft_identity_links.active.first&.player_profile
      return ServiceResult.success(ingame_online: false) unless profile

      session = Minecraft::PlayerSession.active
        .where(player_profile: profile)
        .includes(:server)
        .order(joined_at: :desc)
        .first

      if session
        return ServiceResult.success(
          ingame_online: true,
          ingame_server: session.server.name,
          ingame_server_id: session.server.public_id
        )
      end

      identity = profile.active_identity
      ServiceResult.success(
        ingame_online: false,
        last_seen_ingame_at: identity&.last_seen_ingame_at&.iso8601
      )
    end
  end
end
