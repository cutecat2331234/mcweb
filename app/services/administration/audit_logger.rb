# frozen_string_literal: true

module Administration
  class AuditLogger < ApplicationService
    def initialize(actor: nil, action:, resource: nil, metadata: {}, before_state: {}, after_state: {},
                   ip_address: nil, user_agent: nil, reason: nil, request_id: nil)
      @actor = actor
      @action = action
      @resource = resource
      @metadata = metadata
      @before_state = before_state
      @after_state = after_state
      @ip_address = ip_address
      @user_agent = user_agent
      @reason = reason
      @request_id = request_id.to_s.strip.first(100).presence ||
        metadata_request_id(@metadata)
    end

    def call
      log = AuditLog.create!(
        actor: @actor,
        action: @action,
        resource_type: @resource&.class&.name,
        resource_id: @resource&.id,
        resource_public_id: resource_public_id,
        metadata: @metadata,
        before_state: @before_state,
        after_state: @after_state,
        ip_address: @ip_address,
        user_agent: @user_agent,
        reason: @reason,
        request_id: @request_id
      )

      ServiceResult.success(log)
    end

    private

    def resource_public_id
      return unless @resource.respond_to?(:public_id)

      @resource.public_id
    end

    def metadata_request_id(metadata)
      return unless metadata.respond_to?(:[])

      (metadata[:request_id] || metadata["request_id"] ||
        metadata[:requestId] || metadata["requestId"]).to_s.strip.first(100).presence
    end
  end
end
