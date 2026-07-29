# frozen_string_literal: true

module DataGovernance
  class PlaceRetentionHold < ApplicationService
    def initialize(target:, actor:, reason:, policy_reference: nil, expires_at: nil, request_id: nil)
      @target = target
      @actor = actor
      @reason = reason.to_s.strip
      @policy_reference = policy_reference.to_s.strip.presence
      @expires_at = expires_at
      @request_id = request_id
    end

    def call
      return ServiceResult.failure(error: "reason_required", code: "reason_required") if @reason.blank?

      result = nil
      RetentionHold.transaction do
        policy = RetentionPolicy.lock.find_by(resource_type: @target.class.base_class.name)
        unless policy.nil? || policy.legal_hold_supported?
          result = ServiceResult.failure(
            error: "retention_hold_not_supported",
            code: "retention_hold_not_supported"
          )
          next
        end
        @target = ContentRegistry.lock_record!(@target)

        existing = RetentionHold.effective
          .where(target: @target, policy_reference: @policy_reference)
          .where(reason: @reason)
          .first
        if existing
          result = ServiceResult.success(hold: existing, replayed: true)
          next
        end

        hold = RetentionHold.create!(
          target: @target,
          created_by: @actor,
          reason: @reason,
          policy_reference: @policy_reference,
          expires_at: @expires_at
        )
        Administration::AuditLogger.call(
          actor: @actor,
          action: "data_governance.retention_hold_placed",
          resource: @target,
          request_id: @request_id,
          reason: @reason,
          metadata: {
            hold_public_id: hold.public_id,
            policy_reference: @policy_reference,
            expires_at: @expires_at&.iso8601
          }
        )
        result = ServiceResult.success(hold:, replayed: false)
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
