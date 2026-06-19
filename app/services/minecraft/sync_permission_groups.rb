# frozen_string_literal: true

module Minecraft
  class SyncPermissionGroups < ApplicationService
    def initialize(payload:)
      @payload = payload.deep_stringify_keys
    end

    def call
      player_ref = resolve_player_ref
      groups = Array(@payload["groups"])
      source = @payload["source"].presence || "plugin"

      ActiveRecord::Base.transaction do
        Minecraft::PermissionGroup.where(player_profile: player_ref.profile, source: source).delete_all
        groups.each do |entry|
          Minecraft::PermissionGroup.create!(
            player_profile: player_ref.profile,
            group_key: entry["key"].to_s,
            group_label: entry["label"].to_s.presence,
            weight: entry["weight"].to_i,
            source: source,
            synced_at: Time.current
          )
        end
      end

      ServiceResult.success(player_id: player_ref.public_id, count: groups.size).tap do
        user = player_ref.website_user
        ApplyPermissionGroupMappings.call(user: user, player_profile: player_ref.profile) if user
      end
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
