# frozen_string_literal: true

module Administration
  class AuditLogger < ApplicationService
    def initialize(actor: nil, action:, resource: nil, metadata: {}, before_state: {}, after_state: {},
                   ip_address: nil, user_agent: nil, reason: nil)
      @actor = actor
      @action = action
      @resource = resource
      @metadata = metadata
      @before_state = before_state
      @after_state = after_state
      @ip_address = ip_address
      @user_agent = user_agent
      @reason = reason
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
        reason: @reason
      )

      ServiceResult.success(log)
    end

    private

    def resource_public_id
      return unless @resource.respond_to?(:public_id)

      @resource.public_id
    end
  end
end
