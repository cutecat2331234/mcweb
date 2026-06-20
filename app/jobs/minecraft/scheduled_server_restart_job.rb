# frozen_string_literal: true

module Minecraft
  class ScheduledServerRestartJob < ApplicationJob
    queue_as :maintenance

    def perform
      Minecraft::Server.managed_by_node.find_each do |server|
        schedule = server.metadata["restart_schedule"].to_s.strip
        next if schedule.blank?
        next unless cron_due?(schedule)

        Minecraft::EnqueueNodeTask.call(
          node: server.node,
          server: server,
          task_type: "restart_instance",
          delivery_id: "scheduled-restart-#{server.public_id}-#{Time.current.strftime('%Y%m%d%H')}"
        )
      end
    end

    private

    def cron_due?(expression)
      require "fugit"
      cron = Fugit::Cron.parse(expression)
      return false unless cron

      previous = cron.previous_time(Time.current)
      previous && previous > 5.minutes.ago
    rescue LoadError, StandardError
      false
    end
  end
end
