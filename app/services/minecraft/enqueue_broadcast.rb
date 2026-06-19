# frozen_string_literal: true

module Minecraft
  class EnqueueBroadcast < ApplicationService
    def initialize(message:, title: nil, server: nil, delivery_id: nil)
      @message = message
      @title = title
      @server = server
      @delivery_id = delivery_id
    end

    def call
      servers = target_servers
      return ServiceResult.failure(error: "No Minecraft servers configured.") if servers.empty?

      created = 0
      servers.each do |server|
        Minecraft::ConnectorTask.create!(
          server: server,
          task_type: "broadcast_announcement",
          delivery_id: @delivery_id || SecureRandom.uuid,
          status: "pending",
          payload: {
            message: @message,
            title: @title
          }.compact
        )
        created += 1
      end

      ServiceResult.success(queued: created)
    end

    private

    def target_servers
      return [ @server ] if @server

      online = Minecraft::Server.online_servers.to_a
      online.presence || Minecraft::Server.order(:name).to_a
    end
  end
end
