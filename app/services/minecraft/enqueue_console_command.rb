# frozen_string_literal: true

module Minecraft
  class EnqueueConsoleCommand < ApplicationService
    def initialize(server:, command:, delivery_prefix: nil)
      @server = server
      @command = command.to_s.strip
      @delivery_prefix = delivery_prefix || "console-#{SecureRandom.uuid}"
    end

    def call
      return ServiceResult.failure(error: "Command is required.") if @command.blank?
      return ServiceResult.failure(error: "Server connector is offline.") unless connector_online?

      task = Minecraft::ConnectorTask.create!(
        server: @server,
        task_type: "run_commands",
        delivery_id: "#{@delivery_prefix}-cmd",
        status: "pending",
        payload: { commands: [ @command ] }
      )

      ServiceResult.success(task: task)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def connector_online?
      @server.status == "online" &&
        @server.last_heartbeat_at.present? &&
        @server.last_heartbeat_at > 2.minutes.ago
    end
  end
end
