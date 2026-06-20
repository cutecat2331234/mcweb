# frozen_string_literal: true

module Minecraft
  class SuggestLeastLoadedNode < ApplicationService
    def call
      nodes = Minecraft::Node.where(status: %i[online maintenance]).order(:name)
      return ServiceResult.success(node: nil, load: nil) if nodes.empty?

      loads = nodes.map do |node|
        count = node.servers.count
        stale = node.last_heartbeat_at.nil? || node.last_heartbeat_at < 3.minutes.ago
        { node: node, count: count, stale: stale }
      end

      online = loads.reject { |row| row[:stale] }
      pool = online.presence || loads
      best = pool.min_by { |row| row[:count] }

      ServiceResult.success(node: best[:node], load: best[:count])
    end
  end
end
