# frozen_string_literal: true

module Minecraft
  class ScheduleCollectMetricsJob < ApplicationJob
    queue_as :maintenance

    def perform
      servers = Minecraft::Server
        .managed_by_node
        .joins(:node)
        .where(minecraft_nodes: { status: "online" })
        .to_a
      return if servers.empty?

      operation_servers, legacy_servers = servers.partition do |server|
        server.node.supports_node_operation?("collect_metrics")
      end

      if operation_servers.any?
        Minecraft::EnqueueNodeOperation.call(
          operation_type: "collect_metrics",
          servers: operation_servers,
          idempotency_key: "metrics-group-#{Time.current.to_i / 10.minutes.to_i}"
        )
      end

      # Rolling-upgrade compatibility only. Once an old agent advertises protocol v2,
      # its servers automatically join the single Sidekiq-owned operation group.
      legacy_servers.each do |server|
        Minecraft::EnqueueNodeTask.call(
          node: server.node,
          server: server,
          task_type: "collect_metrics",
          delivery_id: "metrics-legacy-#{server.public_id}-#{Time.current.to_i / 10.minutes.to_i}"
        )
      end
    end
  end
end
