# frozen_string_literal: true

module Minecraft
  class RecordServerAudit < ApplicationService
    def initialize(action:, actor:, server:, metadata: {}, request: nil)
      @action = action
      @actor = actor
      @server = server
      @metadata = metadata
      @request = request
    end

    def call
      AuditLog.record!(
        action: @action,
        actor: @actor,
        resource: @server,
        metadata: @metadata,
        ip_address: @request&.remote_ip,
        user_agent: @request&.user_agent
      )
      ServiceResult.success(true)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
