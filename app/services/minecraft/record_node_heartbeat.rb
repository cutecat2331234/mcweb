# frozen_string_literal: true

module Minecraft
  class RecordNodeHeartbeat < ApplicationService
    AUTHORITATIVE_CAPABILITY_KEYS = %w[
      node_protocol_versions operation_types operation_capabilities
    ].freeze

    def initialize(node:, payload:)
      @node = node
      @payload = payload.deep_stringify_keys
    end

    def call
      heartbeat_metadata = @payload["metadata"].is_a?(Hash) ? @payload["metadata"] : {}
      previously_world_capable = @node.metadata.dig(
        "operation_capabilities", "world_restore_execute"
      ).is_a?(Hash)
      advertises_world_capability = heartbeat_metadata.dig(
        "operation_capabilities", "world_restore_execute"
      ).is_a?(Hash)
      metadata = @node.metadata.merge(heartbeat_metadata)
      AUTHORITATIVE_CAPABILITY_KEYS.each do |key|
        metadata[key] = heartbeat_metadata.fetch(key, key == "operation_capabilities" ? {} : [])
      end
      metadata["world_restore_recovery_required"] = if heartbeat_metadata.key?(
        "world_restore_recovery_required"
      )
        ActiveModel::Type::Boolean.new.cast(heartbeat_metadata["world_restore_recovery_required"])
      else
        previously_world_capable || advertises_world_capability
      end
      metadata["connector_proxy"] = @payload["connector_proxy"] if @payload["connector_proxy"].present?
      if (host_metrics = heartbeat_metadata["host_metrics"]).present?
        metadata["host_metrics"] = host_metrics
        metadata["host_metrics_at"] = Time.current.iso8601
        Minecraft::RecordNodeMetricSnapshot.call(
          node: @node,
          host_metrics: host_metrics,
          metadata: { "source" => "heartbeat" }
        )
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
        urgent_tasks_pending: urgent_work_pending?,
        tasks_wake_at: @node.tasks_wake_at&.iso8601,
        instances: serialize_instances
      )
    end

    private

    def urgent_work_pending?
      @node.node_tasks.where(status: :pending, priority: "urgent").exists? ||
        @node.operation_batches.where(status: "ready").exists?
    end

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
