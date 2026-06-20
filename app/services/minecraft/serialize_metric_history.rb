# frozen_string_literal: true

module Minecraft
  class SerializeMetricHistory < ApplicationService
    def initialize(node: nil, server: nil, duration: 24.hours)
      @node = node
      @server = server
      @duration = duration
    end

    def call
      scope = Minecraft::NodeMetricSnapshot.recent(@duration)
      scope = scope.where(minecraft_node_id: @node.id) if @node
      scope = scope.where(minecraft_server_id: @server.id) if @server

      points = scope.map do |row|
        {
          at: row.recorded_at.iso8601,
          cpu_percent: row.cpu_percent,
          mem_used_bytes: row.mem_used_bytes,
          disk_used_bytes: row.disk_used_bytes,
          tps: row.tps,
          online_players: row.online_players,
          max_players: row.max_players
        }
      end

      ServiceResult.success(points: points)
    end
  end
end
