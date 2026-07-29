# frozen_string_literal: true

module DataGovernance
  class PurgePolicy < ApplicationService
    def initialize(record:, target: record.target, at: Time.current)
      @record = record
      @target = target
      @at = at
    end

    def call
      blockers = []
      blockers << "content_not_soft_deleted" unless @record.status_soft_deleted?

      policy = RetentionPolicy.find_by(resource_type: @record.target_type)
      blockers << "retention_policy_missing" unless policy
      blockers << "indefinite_retention" if policy && policy.retention_days.nil?
      blockers << "retention_period" if @record.purge_after.nil? || @record.purge_after > @at

      if @target
        blockers << "content_not_soft_deleted" unless
          @target.respond_to?(:soft_deleted?) && @target.soft_deleted?
        deletion = DeletionPolicy.call(target: @target)
        blockers.concat(deletion.value.fetch(:blockers)) if deletion.success?
      end

      ServiceResult.success(
        allowed: blockers.empty?,
        blockers: blockers.uniq,
        policy: policy && {
          resource_type: policy.resource_type,
          retention_days: policy.retention_days
        }
      )
    end
  end
end
