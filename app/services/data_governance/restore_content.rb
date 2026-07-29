# frozen_string_literal: true

module DataGovernance
  class RestoreContent < ApplicationService
    def initialize(record:, actor:, reason:, request_id: nil, at: Time.current)
      @record = record
      @actor = actor
      @reason = reason.to_s.strip
      @request_id = request_id
      @at = at
    end

    def call
      return failure("reason_required") if @reason.blank?
      return failure("content_already_purged") if @record.status_purged?
      return ServiceResult.success(record: @record, replayed: true) if @record.status_restored?

      target = @record.target
      return failure("content_target_missing") unless target

      policy = RetentionPolicy.find_by(resource_type: @record.target_type)
      return failure("content_not_restorable") unless policy&.moderator_restorable?

      replayed = false
      @record.with_lock do
        @record.reload
        if @record.status_restored?
          replayed = true
          next
        end
        return failure("content_already_purged") if @record.status_purged?

        target.restore! if target.soft_deleted?
        @record.update!(
          status: "restored",
          restored_by: @actor,
          restored_at: @at,
          restoration_reason: @reason,
          blocker_codes: [],
          last_evaluated_at: @at
        )
        Administration::AuditLogger.call(
          actor: @actor,
          action: "data_governance.content_restored",
          resource: target,
          request_id: @request_id,
          reason: @reason,
          before_state: { deleted_at: @record.soft_deleted_at&.iso8601 },
          after_state: { deleted_at: nil },
          metadata: { lifecycle_public_id: @record.public_id }
        )
      end

      ContentRegistry.after_lifecycle_change(target) unless replayed
      ServiceResult.success(record: @record, replayed:)
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end

    private

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
