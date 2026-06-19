# frozen_string_literal: true

module Minecraft
  class RefreshSkin < ApplicationService
    MOJANG_PROFILE_URL = "https://sessionserver.mojang.com/session/minecraft/profile/%s"

    def initialize(uuid:, platform: "java")
      @uuid = uuid.to_s.delete("-")
      @platform = platform
    end

    def call
      identity = find_identity
      return ServiceResult.failure(error: "identity not found") unless identity

      profile_data = fetch_mojang_textures(identity.external_uuid)
      return ServiceResult.failure(error: "textures not found") unless profile_data

      identity.update!(
        skin_texture_url: profile_data[:texture_url],
        skin_model: profile_data[:skin_model]
      )
      sync_legacy_identity(identity)

      ServiceResult.success(player_id: identity.player_profile.public_id)
    rescue StandardError => e
      ServiceResult.failure(error: e.message)
    end

    private

    def find_identity
      bare = @uuid.delete("-")
      PlayerIdentity.active
                    .where(platform: @platform)
                    .where("external_uuid = ? OR REPLACE(external_uuid, '-', '') = ?", @uuid, bare)
                    .first
    end

    def fetch_mojang_textures(uuid)
      url = format(MOJANG_PROFILE_URL, uuid.delete("-"))
      response = Net::HTTP.get_response(URI(url))
      return nil unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body)
      property = Array(body["properties"]).find { |entry| entry["name"] == "textures" }
      return nil unless property

      decoded = JSON.parse(Base64.decode64(property["value"]))
      texture_url = decoded.dig("textures", "SKIN", "url")
      return nil if texture_url.blank?

      metadata = decoded.dig("textures", "SKIN", "metadata") || {}
      {
        texture_url: texture_url,
        skin_model: metadata["model"].presence || "classic"
      }
    end

    def sync_legacy_identity(identity)
      legacy = Identity.find_by(player_profile: identity.player_profile)
      return unless legacy

      legacy.update!(
        skin_texture_url: identity.skin_texture_url,
        skin_model: identity.skin_model
      )
    end
  end
end
