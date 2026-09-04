# frozen_string_literal: true

module DataGovernance
  class SoftDeleteContent < ApplicationService
    def initialize(
      target:,
      actor:,
      reason:,
      request_id: nil,
      at: Time.current,
      reconcile_existing: false
    )
      @target = target
      @actor = actor
      @reason = reason.to_s.strip
      @request_id = request_id
      @at = at
      @reconcile_existing = reconcile_existing == true
    end

    def call
      return failure("unsupported_resource_type") unless ContentRegistry.supported?(@target)
      return failure("reason_required") if @reason.blank?
      if account_closure_structural_container?
        return failure("account_closure_structural_container_requires_tombstone")
      end

      policy = RetentionPolicy.find_by(resource_type: @target.class.base_class.name)
      return failure("retention_policy_missing") unless policy
      unless policy.user_deletable? || @reconcile_existing
        return failure("content_not_deletable")
      end

      record = nil
      replayed = false
      reconciliation_rejected = false
      @target.with_lock do
        if @reconcile_existing && !@target.soft_deleted?
          reconciliation_rejected = true
          next
        end

        prior_deleted_at = @target.deleted_at
        lifecycle_at = if @reconcile_existing
          prior_deleted_at
        else
          @at
        end
        record = ContentLifecycleRecord.lock.find_or_initialize_by(
          target_type: @target.class.base_class.name,
          target_id: @target.id
        )
        replayed = @target.soft_deleted? && record.persisted? && record.status_soft_deleted?
        next if replayed

        snapshot = ContentRegistry.snapshot(@target)
        @target.soft_delete!(at: lifecycle_at) unless @target.soft_deleted?
        record.assign_attributes(
          status: "soft_deleted",
          deleted_by: @actor,
          restored_by: nil,
          purged_by: nil,
          soft_deleted_at: lifecycle_at,
          purge_after: policy.retention_days.nil? ? nil : lifecycle_at + policy.retention_days.days,
          restored_at: nil,
          purged_at: nil,
          deletion_reason: @reason,
          restoration_reason: nil,
          purge_reason: nil,
          target_snapshot: snapshot,
          blocker_codes: [],
          last_evaluated_at: nil,
          purge_attempts: 0
        )
        record.save!

        Administration::AuditLogger.call(
          actor: @actor,
          action: "data_governance.content_soft_deleted",
          resource: @target,
          request_id: @request_id,
          reason: @reason,
          before_state: { deleted_at: prior_deleted_at&.iso8601 },
          after_state: {
            deleted_at: @target.deleted_at&.iso8601,
            purge_after: record.purge_after&.iso8601
          },
          metadata: {
            lifecycle_public_id: record.public_id,
            retention_days: policy.retention_days,
            reconciled_existing: @reconcile_existing && prior_deleted_at.present?
          }
        )
      end
      return failure("content_not_soft_deleted") if reconciliation_rejected

      ContentRegistry.after_lifecycle_change(@target) unless replayed
      ServiceResult.success(record:, replayed:)
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end

    private

    def account_closure_structural_container?
      return false unless @reason == "account_closure_delete_content"
      return true if @target.is_a?(Community::Topic)
      return true if @target.is_a?(Community::ProfilePost)

      @target.is_a?(Community::Post) && @target.floor_number == 1
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
