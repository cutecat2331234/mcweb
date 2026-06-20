# frozen_string_literal: true

module Minecraft
  class SyncProfileFields < ApplicationService
    def initialize(server:, payload:)
      @server = server
      @payload = payload.deep_stringify_keys
    end

    def call
      player_ref = resolve_player_ref
      access = Minecraft::AssertPlayerOnServer.call(server: @server, player_ref: player_ref)
      return access unless access.success?

      fields = Array(@payload["fields"])
      return ServiceResult.success(player_id: player_ref.public_id, updated: 0) if fields.blank?

      updated = 0
      fields.each do |entry|
        key = entry["key"].to_s
        next if key.blank?

        Minecraft::ProfileFieldValue.upsert(
          {
            player_profile_id: player_ref.profile.id,
            field_key: key,
            value: entry["value"].to_s,
            updated_by: "plugin",
            created_at: Time.current,
            updated_at: Time.current
          },
          unique_by: %i[player_profile_id field_key]
        )
        updated += 1
      end

      ServiceResult.success(player_id: player_ref.public_id, updated: updated)
    end

    private

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
