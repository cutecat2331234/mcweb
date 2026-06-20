# frozen_string_literal: true

module Minecraft
  class ScheduledBackupWorldJob < ApplicationJob
    queue_as :maintenance

    def perform
      Minecraft::Server.managed_by_node.find_each do |server|
        next unless backup_enabled?(server)
        next unless backup_due?(server)

        backup_dir = server.metadata["backup_directory"].presence ||
          File.join(server.working_directory.to_s, "backups")
        filename = "world-#{Time.current.strftime('%Y%m%d-%H%M%S')}.tar.gz"
        dest = File.join(backup_dir, filename)

        Minecraft::EnqueueNodeTask.call(
          node: server.node,
          server: server,
          task_type: "backup_world",
          delivery_id: "backup-#{server.public_id}-#{Time.current.to_i}",
          payload: {
            source: server.metadata["world_directory"].presence || "world",
            destination: dest
          }
        )
      end
    end

    private

    def backup_enabled?(server)
      val = server.metadata["backup_enabled"]
      return true if val.nil? && SiteSetting.get("minecraft.backup.enabled", "false") == "true"

      ActiveModel::Type::Boolean.new.cast(val)
    end

    def backup_due?(server)
      schedule = server.metadata["backup_schedule"].presence ||
        SiteSetting.get("minecraft.backup.schedule", "0 3 * * *")
      return false if schedule.blank?

      require "fugit"
      cron = Fugit::Cron.parse(schedule)
      return false unless cron

      previous = cron.previous_time(Time.current)
      previous && previous > 5.minutes.ago
    rescue LoadError, StandardError
      false
    end
  end
end
