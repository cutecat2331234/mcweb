# frozen_string_literal: true

module Minecraft
  class SyncPresence < ApplicationService
    def initialize(server:, payload:)
      @server = server
      @payload = payload.deep_stringify_keys
    end

    def call
      player_ref = resolve_player_ref
      identity = player_ref.active_identity
      return ServiceResult.failure(error: "Unable to resolve player.") unless identity

      identity.update!(
        username: @payload["username"].presence || identity.username,
        skin_texture_url: @payload["skin_texture"].presence || identity.skin_texture_url,
        skin_model: @payload["skin_model"].presence || identity.skin_model,
        last_seen_ingame_at: Time.current,
        primary_server: @server
      )

      sync_legacy_identity(player_ref, identity)

      if identity.skin_texture_url.blank? && identity.external_uuid.present?
        Minecraft::RefreshSkinJob.perform_later(identity.external_uuid, platform: identity.platform)
      end

      event = @payload["event"].presence || "player.join"
      Minecraft::Integration::ActionRunner.call(
        event_key: event,
        event_id: "presence-#{player_ref.public_id}-#{@server.id}-#{Time.current.to_i}",
        payload: @payload.merge("player_id" => player_ref.public_id, "server_id" => @server.public_id)
      )

      ServiceResult.success(player_id: player_ref.public_id)
    end

    private

    def sync_legacy_identity(player_ref, identity)
      legacy = Minecraft::Identity.find_by(player_profile: player_ref.profile)
      return unless legacy

      legacy.update!(
        username: identity.username,
        skin_texture_url: identity.skin_texture_url,
        skin_model: identity.skin_model,
        last_seen_ingame_at: identity.last_seen_ingame_at,
        server: @server
      )
    end

    def resolve_player_ref
      if @payload["player_id"].present?
        Minecraft::PlayerRef.find_by_canonical(@payload["player_id"]) ||
          raise(ActiveRecord::RecordNotFound)
      else
        Minecraft::PlayerRef.resolve(
          uuid: @payload.fetch("uuid"),
          platform: @payload["platform"].presence || "java",
          username: @payload["username"]
        )
      end
    end
  end
end
