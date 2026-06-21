# frozen_string_literal: true

module Minecraft
  class RecordNodeMetricSnapshot < ApplicationService
    def initialize(node:, host_metrics: nil, server: nil, instance_metrics: nil, metadata: nil)
      @node = node
      @host_metrics = (host_metrics || {}).stringify_keys
      @server = server
      @instance_metrics = (instance_metrics || {}).stringify_keys
      @metadata = (metadata || {}).stringify_keys
    end

    def call
      snapshot = Minecraft::NodeMetricSnapshot.create!(
        node: @node,
        server: @server,
        cpu_percent: numeric(@host_metrics["cpu_percent"]),
        mem_used_bytes: bytes(@host_metrics["mem_used_bytes"]),
        mem_total_bytes: bytes(@host_metrics["mem_total_bytes"]),
        disk_used_bytes: bytes(@host_metrics["disk_used_bytes"]),
        disk_total_bytes: bytes(@host_metrics["disk_total_bytes"]),
        tps: numeric(@instance_metrics["tps"]),
        online_players: int(@instance_metrics["online_players"]),
        max_players: int(@instance_metrics["max_players"]),
        metadata: @metadata,
        recorded_at: Time.current
      )

      prune_old_snapshots!
      ServiceResult.success(snapshot: snapshot)
  rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def numeric(value)
      return nil if value.nil?

      value.to_f
    end

    def bytes(value)
      return nil if value.nil?

      value.to_i
    end

    def int(value)
      return nil if value.nil?

      value.to_i
    end

    def prune_old_snapshots!
      Minecraft::NodeMetricSnapshot
        .where(minecraft_node_id: @node.id)
        .where("recorded_at < ?", 7.days.ago)
        .delete_all
    end
  end
end
