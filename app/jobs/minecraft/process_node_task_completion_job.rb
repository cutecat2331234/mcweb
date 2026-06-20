# frozen_string_literal: true

module Minecraft
  class ProcessNodeTaskCompletionJob < ApplicationJob
    queue_as :minecraft

    def perform(task_id)
      task = Minecraft::NodeTask.find_by(id: task_id)
      return unless task&.completed?

      case task.task_type
      when "start_instance"
        chain_fulfillment_after_start!(task)
      end
    end

    private

    def chain_fulfillment_after_start!(task)
      return unless task.server_id

      server = task.server
      return unless server

      if server.process_running?
        Minecraft::ChainFulfillmentAfterStartJob.perform_later(task.server_id)
      else
        Minecraft::PollInstanceProcessStateJob.perform_later(task.server_id)
      end
    end
  end
end
