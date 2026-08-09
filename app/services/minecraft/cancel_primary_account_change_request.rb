# frozen_string_literal: true

module Minecraft
  class CancelPrimaryAccountChangeRequest < ApplicationService
    def initialize(request_record:, actor:, lock_version:)
      @request_record = request_record
      @actor = actor
      @lock_version = Integer(lock_version, exception: false)
    end

    def call
      return failure(:primary_account_forbidden) unless @actor&.id == @request_record.user_id
      return failure(:primary_account_lock_version_required) unless @lock_version

      changed = false
      result = nil
      @request_record.user.with_lock do
        @request_record.lock!
        if @request_record.cancelled?
          result = ServiceResult.success(request: @request_record, replayed: true)
          next
        end
        unless @request_record.pending?
          result = failure(:primary_account_request_not_pending)
          next
        end
        unless @request_record.lock_version == @lock_version
          result = failure(:primary_account_request_stale)
          next
        end

        @request_record.update!(
          status: "cancelled",
          decided_by: @actor,
          decision_reason: "cancelled_by_requester",
          resolved_at: Time.current
        )
        Administration::AuditLogger.call(
          actor: @actor,
          action: "minecraft.primary_account_change_cancelled",
          resource: @request_record,
          metadata: { user_id: @request_record.user_id }
        )
        changed = true
        result = ServiceResult.success(request: @request_record, replayed: false)
      end

      Minecraft::PrimaryAccountNotifications.request_resolved(@request_record) if changed
      result
    rescue ActiveRecord::StaleObjectError
      failure(:primary_account_request_stale)
    end

    private

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
