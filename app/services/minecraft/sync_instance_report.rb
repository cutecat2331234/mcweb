# frozen_string_literal: true

module Minecraft
  class SyncInstanceReport < ApplicationService
    def initialize(node:, server:, payload:)
      @node = node
      @server = server
      @payload = payload.deep_stringify_keys
    end

    def call
      return ServiceResult.failure(error: "Server is not managed by this node.") unless @server.minecraft_node_id == @node.id

      attrs = {}
      attrs[:process_state] = @payload["process_state"] if @payload["process_state"].present?

      metrics = @payload["metrics"]
      if metrics.present?
        metadata = @server.metadata.merge("last_metrics" => metrics, "last_metrics_at" => Time.current.iso8601)
        attrs[:metadata] = metadata
        instance = metrics["instance"] || {}
        host = metrics["host"] || {}
        snapshot = @server.server_snapshots.order(created_at: :desc).first
        Minecraft::RecordNodeMetricSnapshot.call(
          node: @node,
          server: @server,
          host_metrics: host,
          instance_metrics: {
            "tps" => snapshot&.tps,
            "online_players" => snapshot&.online_players,
            "max_players" => snapshot&.max_players,
            "process_state" => instance["process_state"]
          }
        )
      end

      @server.update!(attrs) if attrs.any?

      ServiceResult.success(server_id: @server.public_id, process_state: @server.process_state)
    end
  end
end
