# frozen_string_literal: true

module Minecraft
  class ScheduledBackupWorldJob < ApplicationJob
    queue_as :maintenance

    def perform
      Minecraft::Server.managed_by_node.find_each do |server|
        next unless backup_enabled?(server)

        occurrence = backup_occurrence(server)
        next unless occurrence

        backup_dir = server.metadata["backup_directory"].presence ||
          File.join(server.working_directory.to_s, "backups")
        filename = "world-#{Time.current.strftime('%Y%m%d-%H%M%S')}.tar.gz"
        dest = File.join(backup_dir, filename)

        Minecraft::EnqueueNodeTask.call(
          node: server.node,
          server: server,
          task_type: "backup_world",
          # Key the delivery on the scheduled occurrence (not Time.now) so a retry or a
          # second wrapper tick within the window dedups to one backup per occurrence.
          delivery_id: "backup-#{server.public_id}-#{occurrence.strftime('%Y%m%d%H%M')}",
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

    # Returns the most recent scheduled occurrence if it falls within the wrapper-cron
    # cadence (this job runs every 30 min), else nil. The window must be >= the run
    # interval, otherwise occurrences not aligned to the */30 ticks are silently missed.
    def backup_occurrence(server)
      schedule = server.metadata["backup_schedule"].presence ||
        SiteSetting.get("minecraft.backup.schedule", "0 3 * * *")
      return nil if schedule.blank?

      require "fugit"
      cron = Fugit::Cron.parse(schedule)
      return nil unless cron

      previous = cron.previous_time(Time.current)
      return nil unless previous && previous > 30.minutes.ago

      previous
    rescue LoadError, StandardError
      nil
    end
  end
end
