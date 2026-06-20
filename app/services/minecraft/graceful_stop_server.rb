# frozen_string_literal: true

module Minecraft
  class GracefulStopServer < ApplicationService
    DEFAULT_COUNTDOWN = 30
    DEFAULT_COMMANDS = %w[save-all stop].freeze

    def initialize(server:)
      @server = server
    end

    def call
      return ServiceResult.failure(error: "Server is not bound to a node.") unless @server.node_managed?

      unless graceful_stop_enabled?
        return raw_stop
      end

      connector_online = connector_connected?
      countdown = graceful_countdown_seconds

      if connector_online && countdown.positive?
        Minecraft::ConnectorTask.create!(
          server: @server,
          task_type: "broadcast_announcement",
          delivery_id: "#{delivery_prefix}-announce",
          status: "pending",
          payload: { message: graceful_message(countdown) }
        )
      end

      if connector_online && graceful_commands.any?
        Minecraft::ConnectorTask.create!(
          server: @server,
          task_type: "run_commands",
          delivery_id: "#{delivery_prefix}-commands",
          status: "pending",
          payload: { commands: graceful_commands }
        )
      end

      delay = connector_online ? countdown.seconds + 5.seconds : 0.seconds
      @server.update!(process_state: :stopping)

      Minecraft::EnqueueStopInstanceJob.set(wait: delay).perform_later(
        @server.id,
        payload: { timeout_seconds: stop_timeout_seconds }
      )

      ServiceResult.success(graceful: true, delay_seconds: delay.to_i)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def delivery_prefix
      @delivery_prefix ||= "graceful-#{SecureRandom.uuid}"
    end

    def graceful_stop_enabled?
      return false unless SiteSetting.get("minecraft.graceful_stop.enabled", "true") == "true"

      val = @server.metadata["graceful_stop_enabled"]
      return true if val.nil?

      ActiveModel::Type::Boolean.new.cast(val)
    end

    def connector_connected?
      @server.status == "online" &&
        @server.last_heartbeat_at.present? &&
        @server.last_heartbeat_at > 2.minutes.ago
    end

    def graceful_countdown_seconds
      (@server.metadata["graceful_stop_countdown"] ||
        SiteSetting.get("minecraft.graceful_stop.countdown_seconds", DEFAULT_COUNTDOWN.to_s)).to_i
    end

    def graceful_message(countdown)
      template = @server.metadata["graceful_stop_message"].presence ||
        SiteSetting.get("minecraft.graceful_stop.message", "Server shutting down in {seconds} seconds")
      template.gsub("{seconds}", countdown.to_s)
    end

    def graceful_commands
      raw = @server.metadata["graceful_stop_commands"]
      if raw.nil?
        default = SiteSetting.get("minecraft.graceful_stop.commands", DEFAULT_COMMANDS.join(","))
        return default.split(",").map(&:strip).reject(&:blank?)
      end

      Array(raw).map(&:to_s).reject(&:blank?)
    end

    def stop_timeout_seconds
      (@server.metadata["graceful_stop_timeout"] || 60).to_i
    end

    def raw_stop
      result = Minecraft::EnqueueNodeTask.call(
        node: @server.node,
        server: @server,
        task_type: "stop_instance",
        payload: { timeout_seconds: stop_timeout_seconds }
      )
      return result if result.failure?

      ServiceResult.success(graceful: false, task: result.value[:task])
    end
  end
end
