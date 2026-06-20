# frozen_string_literal: true

module Minecraft
  class ReconcileProcessStateJob < ApplicationJob
    queue_as :maintenance

    NOTIFY_COOLDOWN = 1.hour

    def perform
      Minecraft::Server.managed_by_node.find_each do |server|
        connector_online = server.status == "online" &&
          server.last_heartbeat_at.present? &&
          server.last_heartbeat_at > 2.minutes.ago
        process_running = server.process_running?

        next if connector_online == process_running

        metadata = server.metadata.merge(
          "process_mismatch_alert" => {
            "at" => Time.current.iso8601,
            "connector_online" => connector_online,
            "process_state" => server.process_state
          }
        )
        server.update!(metadata: metadata)

        notify_process_mismatch!(server, connector_online) if should_notify_mismatch?(server)
      end
    end

    private

    def should_notify_mismatch?(server)
      last = server.metadata["process_mismatch_notified_at"]
      return true if last.blank?

      Time.zone.parse(last) < NOTIFY_COOLDOWN.ago
    rescue ArgumentError
      true
    end

    def notify_process_mismatch!(server, connector_online)
      state_label = connector_online ? "connector online but process not running" : "process running but connector offline"

      Minecraft::NotifyStaff.call(
        notification_type: "minecraft.process_mismatch",
        title: "Minecraft process mismatch: #{server.name}",
        body: "#{server.name} — #{state_label} (process_state=#{server.process_state}).",
        metadata: {
          path: "/admin/minecraft/servers/#{server.public_id}",
          server_id: server.public_id,
          process_state: server.process_state,
          connector_online: connector_online
        }
      )

      server.update!(
        metadata: server.metadata.merge("process_mismatch_notified_at" => Time.current.iso8601)
      )
    end
  end
end
