# frozen_string_literal: true

module DataGovernance
  class ReleaseRetentionHold < ApplicationService
    def initialize(hold:, actor:, reason:, request_id: nil)
      @hold = hold
      @actor = actor
      @reason = reason.to_s.strip
      @request_id = request_id
    end

    def call
      return ServiceResult.failure(error: "reason_required", code: "reason_required") if @reason.blank?
      return ServiceResult.success(hold: @hold, replayed: true) if @hold.released?

      RetentionHold.transaction do
        @hold.lock!
        return ServiceResult.success(hold: @hold, replayed: true) if @hold.released?

        @hold.update!(
          status: :released,
          released_by: @actor,
          released_at: Time.current,
          release_reason: @reason
        )
        Administration::AuditLogger.call(
          actor: @actor,
          action: "data_governance.retention_hold_released",
          resource: @hold.resolved_target,
          request_id: @request_id,
          reason: @reason,
          metadata: { hold_public_id: @hold.public_id }
        )
      end

      ServiceResult.success(hold: @hold, replayed: false)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
