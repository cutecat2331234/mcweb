# frozen_string_literal: true

module Commerce
  class DispatchMembershipCommands < ApplicationService
    def initialize(user:, membership_type:, commands:, server: nil)
      @user = user
      @membership_type = membership_type
      @commands = commands
      @server = server
    end

    def call
      return ServiceResult.success(skipped: true) unless @membership_type.game_permission_enabled?

      payload_result = Commerce::BuildMembershipCommandPayload.call(
        user: @user,
        membership_type: @membership_type,
        commands: @commands
      )
      return payload_result if payload_result.failure?

      servers = target_servers
      return ServiceResult.failure(error: "no_minecraft_server") if servers.empty?

      delivery_id = "mbr_#{SecureRandom.alphanumeric(20)}"
      servers.each do |server|
        Minecraft::ConnectorTask.create!(
          server: server,
          task_type: "run_commands",
          delivery_id: delivery_id,
          status: "pending",
          payload: payload_result.value
        )
      end

      ServiceResult.success(queued: servers.size)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def target_servers
      return [ @server ] if @server

      candidates = Minecraft::Server.online_servers.process_running.to_a
      running = candidates.presence || Minecraft::Server.online_servers.to_a
      (running.presence || Minecraft::Server.order(:name).limit(1).to_a)
    end
  end
end
