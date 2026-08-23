# frozen_string_literal: true

module Minecraft
  class ScheduledBackupWorldJob < ApplicationJob
    queue_as :maintenance

    def perform
      Minecraft::Server.managed_by_node.find_each do |server|
        next unless backup_enabled?(server)

        occurrence = backup_occurrence(server)
        next unless occurrence

        Minecraft::CreateWorldBackup.call(
          server: server,
          purpose: "scheduled",
          request_id: occurrence_request_id(server, occurrence)
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

    def occurrence_request_id(server, occurrence)
      hex = Digest::SHA256.hexdigest(
        "scheduled-world-backup:v1:#{server.public_id}:#{occurrence.utc.iso8601}"
      ).first(32)
      [ hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12] ].join("-")
    end
  end
end
