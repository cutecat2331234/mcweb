# frozen_string_literal: true

module Minecraft
  class ExpirePrimaryAccountChangeRequests < ApplicationService
    def initialize(user: nil, at: Time.current)
      @user = user
      @at = at
    end

    def call
      scope = Minecraft::PrimaryAccountChangeRequest.past_deadline(@at)
      scope = scope.where(user: @user) if @user
      expired = []

      scope.find_each do |request_record|
        request_record.user.with_lock do
          request_record.lock!
          next unless request_record.past_deadline?(at: @at)

          request_record.update!(
            status: "expired",
            resolved_at: @at,
            decision_reason: "request_expired"
          )
          Administration::AuditLogger.call(
            action: "minecraft.primary_account_change_expired",
            resource: request_record,
            metadata: {
              user_id: request_record.user_id,
              target_identity_link_id: request_record.target_identity_link_id
            }
          )
          expired << request_record
        end
      end

      expired.each { |request_record| Minecraft::PrimaryAccountNotifications.request_resolved(request_record) }
      ServiceResult.success(expired_count: expired.length, requests: expired)
    end
  end
end
