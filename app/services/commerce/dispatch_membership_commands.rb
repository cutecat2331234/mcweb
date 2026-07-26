# frozen_string_literal: true

module Commerce
  class DispatchMembershipCommands < ApplicationService
    def initialize(user:, membership_type:, commands:, server: nil, idempotency_key: nil)
      @user = user
      @membership_type = membership_type
      @commands = commands
      @server = server
      @idempotency_key = idempotency_key.to_s.presence
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

      delivery_prefix = @idempotency_key || "mbr_#{SecureRandom.alphanumeric(20)}"
      queued = 0
      retried = 0

      servers.each do |server|
        delivery_id = "#{delivery_prefix}:server:#{server.id}"
        task = Minecraft::ConnectorTask.find_or_initialize_by(delivery_id: delivery_id)

        if task.new_record?
          task.assign_attributes(
            server: server,
            task_type: "run_commands",
            status: "pending",
            payload: payload_result.value
          )
          task.save!
          queued += 1
          next
        end

        unless task.minecraft_server_id == server.id && task.task_type == "run_commands"
          return ServiceResult.failure(error: "membership_command_delivery_conflict")
        end

        next unless task.failed?

        task.update!(
          status: "pending",
          claimed_at: nil,
          completed_at: nil,
          result: {},
          payload: payload_result.value
        )
        retried += 1
      end

      ServiceResult.success(queued: queued, retried: retried, existing: servers.size - queued - retried)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def target_servers
      return [ @server ] if @server

      candidates = Minecraft::Server.online_servers.process_running.order(:id).to_a
      running = candidates.presence || Minecraft::Server.online_servers.order(:id).to_a
      running.presence || Minecraft::Server.order(:id).limit(1).to_a
    end
  end
end
