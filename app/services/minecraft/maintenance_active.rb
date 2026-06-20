# frozen_string_literal: true

module Minecraft
  class MaintenanceActive < ApplicationService
    def initialize(server: nil)
      @server = server
    end

    def call
      if @server
        active = server_in_maintenance?(@server)
        return ServiceResult.success(active: active, server: @server)
      end

      any = Minecraft::Server.where(status: :maintenance).exists? ||
        Minecraft::Node.where(status: :maintenance).exists?
      ServiceResult.success(active: any)
    end

    def self.pause_fulfillment?
      SiteSetting.get("minecraft.commerce.pause_fulfill_during_maintenance", "true") == "true"
    end

    private

    def server_in_maintenance?(server)
      server.status == "maintenance" || server.node&.status == "maintenance"
    end
  end
end
