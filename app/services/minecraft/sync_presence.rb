# frozen_string_literal: true

module Minecraft
  class SyncPresence < ApplicationService
    JOIN_EVENTS = %w[player.join player.first_join join].freeze
    QUIT_EVENTS = %w[player.quit quit leave].freeze

    def initialize(server:, payload:)
      @server = server
      @payload = payload.deep_stringify_keys
    end

    def call
      player_ref = resolve_player_ref
      identity = player_ref.active_identity
      return ServiceResult.failure(error: "Unable to resolve player.") unless identity

      event = @payload["event"].presence || "player.join"

      access = verify_event_access!(player_ref: player_ref, event: event)
      return access unless access.success?

      identity.update!(
        username: @payload["username"].presence || identity.username,
        skin_texture_url: safe_skin_texture_url(@payload["skin_texture"]) || identity.skin_texture_url,
        skin_model: @payload["skin_model"].presence || identity.skin_model,
        last_seen_ingame_at: Time.current,
        primary_server: @server
      )

      sync_legacy_identity(player_ref, identity)

      Minecraft::ManagePlayerSessions.call(
        server: @server,
        player_profile: player_ref.profile,
        username: @payload["username"].presence || identity.username,
        event: event
      )

      if identity.skin_texture_url.blank? && identity.external_uuid.present?
        Minecraft::RefreshSkinJob.perform_later(identity.external_uuid, platform: identity.platform)
      end

      user = player_ref.website_user
      Commerce::SyncMembershipPermissionsJob.perform_later(user.id) if user

      Minecraft::RunIntegrationActionJob.perform_later(
        event_key: event,
        event_id: "presence-#{player_ref.public_id}-#{@server.id}-#{Time.current.to_i}",
        payload: @payload.merge("player_id" => player_ref.public_id, "server_id" => @server.public_id)
      )

      ServiceResult.success(player_id: player_ref.public_id)
    end

    private

    def verify_event_access!(player_ref:, event:)
      if quit_event?(event)
        return Minecraft::AssertPlayerOnServer.call(server: @server, player_ref: player_ref)
      end

      if join_event?(event)
        roster_check = Minecraft::ConnectorOnlineRoster.validate_presence_roster!(server: @server, payload: @payload)
        return roster_check unless roster_check.success?
      end

      existing = Minecraft::AssertPlayerOnServer.call(server: @server, player_ref: player_ref)
      return existing if existing.success?

      if join_event?(event)
        uuid = Minecraft::ConnectorOnlineRoster.normalize_uuid(@payload["uuid"])
        if Minecraft::ConnectorOnlineRoster.includes?(server: @server, uuid: uuid)
          return ServiceResult.success
        end

        return ServiceResult.failure(error: "Player is not associated with this server.")
      end

      ServiceResult.failure(error: "Player is not associated with this server.")
    end

    def join_event?(event)
      event.to_s.in?(JOIN_EVENTS)
    end

    def quit_event?(event)
      event.to_s.in?(QUIT_EVENTS)
    end

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

    def safe_skin_texture_url(url)
      location = url.presence
      return nil if location.blank?
      return location if UrlSafety.safe_image_src?(location)

      nil
    end
  end
end
