# frozen_string_literal: true

module DataGovernance
  class UpdateRetentionPolicy < ApplicationService
    def initialize(policy:, actor:, attributes:, reason:, request_id: nil)
      @policy = policy
      @actor = actor
      @attributes = attributes.to_h.symbolize_keys.slice(
        :retention_days,
        :user_deletable,
        :moderator_restorable,
        :legal_hold_supported,
        :notes
      )
      @reason = reason.to_s.strip
      @request_id = request_id
    end

    def call
      return failure("reason_required") if @reason.blank?

      result = nil

      RetentionPolicy.transaction do
        @policy.lock!
        if disabling_hold_support_with_active_holds?
          result = failure("active_retention_holds_exist")
          next
        end

        before_state = @policy.attributes.slice(
          "retention_days",
          "user_deletable",
          "moderator_restorable",
          "legal_hold_supported",
          "notes"
        )
        @policy.update!(@attributes)
        reschedule_soft_deleted_content!
        Administration::AuditLogger.call(
          actor: @actor,
          action: "data_governance.retention_policy_updated",
          resource: @policy,
          request_id: @request_id,
          reason: @reason,
          before_state:,
          after_state: @policy.attributes.slice(*before_state.keys),
          metadata: { resource_type: @policy.resource_type }
        )
        result = ServiceResult.success(policy: @policy)
      end

      result
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end

    private

    def disabling_hold_support_with_active_holds?
      @attributes[:legal_hold_supported] == false &&
        @policy.legal_hold_supported? &&
        RetentionHold.effective.where(target_type: @policy.resource_type).exists?
    end

    def reschedule_soft_deleted_content!
      scope = ContentLifecycleRecord.status_soft_deleted.where(target_type: @policy.resource_type)
      if @policy.retention_days.nil?
        scope.update_all(purge_after: nil, updated_at: Time.current)
        return
      end

      scope.find_each do |record|
        record.update!(purge_after: record.soft_deleted_at + @policy.retention_days.days)
      end
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
