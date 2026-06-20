# frozen_string_literal: true

module Minecraft
  class RecordNodeHeartbeat < ApplicationService
    def initialize(node:, payload:)
      @node = node
      @payload = payload.deep_stringify_keys
    end

    def call
      metadata = @node.metadata.merge(@payload.fetch("metadata", {}))
      metadata["connector_proxy"] = @payload["connector_proxy"] if @payload["connector_proxy"].present?
      if (host_metrics = @payload.dig("metadata", "host_metrics")).present?
        metadata["host_metrics"] = host_metrics
        metadata["host_metrics_at"] = Time.current.iso8601
        Minecraft::RecordNodeMetricSnapshot.call(node: @node, host_metrics: host_metrics)
      end

      @node.update!(
        last_heartbeat_at: Time.current,
        status: :online,
        metadata: metadata,
        hostname: @payload["hostname"].presence || @node.hostname
      )

      ServiceResult.success(
        node_id: @node.public_id,
        status: "ok",
        instances: serialize_instances
      )
    end

    private

    def serialize_instances
      @node.servers.order(:name).map do |server|
        {
          server_id: server.public_id,
          name: server.name,
          process_driver: server.process_driver,
          process_config: server.process_config,
          process_state: server.process_state,
          working_directory: server.working_directory,
          connection_mode: server.connection_mode,
          proxy_listen_url: server.effective_proxy_listen_url
        }
      end
    end
  end
end
