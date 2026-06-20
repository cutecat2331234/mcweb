# frozen_string_literal: true

module Minecraft
  class MarkStaleNodesOfflineJob < ApplicationJob
    queue_as :maintenance

    STALE_AFTER = 3.minutes
    NOTIFY_COOLDOWN = 1.hour

    def perform
      Minecraft::Node
        .where(status: :online)
        .where("last_heartbeat_at IS NULL OR last_heartbeat_at < ?", STALE_AFTER.ago)
        .find_each do |node|
          node.update!(status: :offline)
          notify_node_offline!(node) if should_notify_offline?(node)
        end
    end

    private

    def should_notify_offline?(node)
      last = node.metadata["offline_notified_at"]
      return true if last.blank?

      Time.zone.parse(last) < NOTIFY_COOLDOWN.ago
    rescue ArgumentError
      true
    end

    def notify_node_offline!(node)
      Minecraft::NotifyStaff.call(
        notification_type: "minecraft.node_offline",
        title: "Minecraft node offline: #{node.name}",
        body: "Node #{node.name} (#{node.hostname}) missed heartbeats and was marked offline.",
        metadata: {
          path: "/admin/minecraft/nodes/#{node.public_id}",
          node_id: node.public_id
        }
      )

      node.update!(
        metadata: node.metadata.merge("offline_notified_at" => Time.current.iso8601)
      )
    end
  end
end
