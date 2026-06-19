# frozen_string_literal: true

module Minecraft
  class RecordHeartbeat < ApplicationService
    def initialize(server:, payload:)
      @server = server
      @payload = payload.deep_stringify_keys
    end

    def call
      @server.heartbeat!
      snapshot_attrs = {
        online_players: @payload["online_players"].to_i,
        max_players: @payload["max_players"].to_i,
        tps: @payload["tps"]&.to_f,
        memory_used_bytes: @payload.dig("memory", "used")&.to_i,
        memory_max_bytes: @payload.dig("memory", "max")&.to_i,
        motd: @payload["motd"].to_s.presence,
        version: @payload["version"].to_s.presence,
        plugins: Array(@payload["plugins"]),
        worlds: Array(@payload["worlds"]),
        metadata: @payload.except("online_players", "max_players", "tps", "memory", "motd", "version", "plugins", "worlds")
      }

      if snapshot_attrs.values_at(:online_players, :max_players, :tps, :motd, :version).any?(&:present?) ||
         snapshot_attrs[:plugins].any? || snapshot_attrs[:worlds].any?
        Minecraft::ServerSnapshot.create!(server: @server, **snapshot_attrs)
      end

      ServiceResult.success(server_id: @server.public_id, status: "ok")
    end
  end
end
