# frozen_string_literal: true

module Minecraft
  class AggregatePlayerStatus < ApplicationService
    WEBSITE_ONLINE_WINDOW = 5.minutes

    def initialize(scope: :active)
      @scope = scope
    end

    def call
      sessions = base_scope.includes(
        player_profile: { identity_links: :user },
        server: []
      )

      players = sessions.map { |session| serialize_session(session) }
      ServiceResult.success(players: players)
    end

    private

    def base_scope
      case @scope
      when :active
        Minecraft::PlayerSession.active.order(joined_at: :desc)
      else
        Minecraft::PlayerSession.order(joined_at: :desc).limit(200)
      end
    end

    def serialize_session(session)
      profile = session.player_profile
      user = profile.identity_links.active.includes(:user).first&.user
      identity = profile.active_identity

      {
        username: session.username,
        player_id: profile.public_id,
        player_uuid: identity&.external_uuid,
        ingame_online: session.active?,
        ingame_server: session.server.name,
        ingame_server_id: session.server.public_id,
        joined_at: session.joined_at.iso8601,
        website_online: user ? website_online?(user) : false,
        linked_user: user ? { id: user.public_id, username: user.username } : nil,
        last_seen_ingame_at: identity&.last_seen_ingame_at&.iso8601,
        last_seen_at: user&.last_seen_at&.iso8601
      }
    end

    def website_online?(user)
      user.last_seen_at.present? && user.last_seen_at > WEBSITE_ONLINE_WINDOW.ago
    end
  end
end
