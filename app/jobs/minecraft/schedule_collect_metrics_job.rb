# frozen_string_literal: true

module Minecraft
  class ScheduleCollectMetricsJob < ApplicationJob
    queue_as :maintenance

    def perform
      Minecraft::Server.managed_by_node.find_each do |server|
        next unless server.node&.status == "online"

        Minecraft::EnqueueNodeTask.call(
          node: server.node,
          server: server,
          task_type: "collect_metrics",
          delivery_id: "metrics-#{server.public_id}-#{Time.current.to_i}"
        )
      end
    end
  end
end
