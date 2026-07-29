# frozen_string_literal: true

module DataGovernance
  class PermanentlyPurgeContent < ApplicationService
    def initialize(record:, actor: nil, reason:, request_id: nil, at: Time.current)
      @record = record
      @actor = actor
      @reason = reason.to_s.strip
      @request_id = request_id
      @at = at
    end

    def call
      return failure("reason_required") if @reason.blank?
      return ServiceResult.success(record: @record, replayed: true) if @record.status_purged?

      result = nil
      @record.with_lock do
        @record.reload
        if @record.status_purged?
          result = ServiceResult.success(record: @record, replayed: true)
          next
        end

        target = @record.target
        unless target
          mark_missing_target_purged!
          result = ServiceResult.success(record: @record, replayed: true, target_missing: true)
          next
        end
        target = ContentRegistry.lock_record!(target)

        policy = PurgePolicy.call(record: @record, target:, at: @at)
        blockers = policy.value.fetch(:blockers)
        @record.update!(
          blocker_codes: blockers,
          last_evaluated_at: @at,
          purge_attempts: @record.purge_attempts + 1
        )
        if blockers.any?
          audit_blocked_attempt(target, blockers)
          result = ServiceResult.failure(
            error: "content_purge_blocked",
            code: "content_purge_blocked",
            value: { record: @record, blockers: blockers }
          )
          next
        end

        snapshot = ContentRegistry.purged_snapshot(target)
        ContentRegistry.before_permanent_purge(target)
        target.destroy!
        @record.update!(
          status: "purged",
          purged_by: @actor,
          purged_at: @at,
          purge_reason: @reason,
          target_snapshot: snapshot,
          blocker_codes: [],
          last_evaluated_at: @at
        )
        Administration::AuditLogger.call(
          actor: @actor,
          action: "data_governance.content_purged",
          resource: target,
          request_id: @request_id,
          reason: @reason,
          before_state: snapshot,
          after_state: { purged_at: @at.iso8601 },
          metadata: {
            lifecycle_public_id: @record.public_id,
            scheduled: @actor.nil?
          }
        )
        result = ServiceResult.success(record: @record, replayed: false)
      end

      result
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => error
      ServiceResult.failure(
        error: "content_purge_failed",
        code: "content_purge_failed",
        value: { exception: error.class.name }
      )
    end

    private

    def mark_missing_target_purged!
      snapshot = ContentRegistry.scrubbed_snapshot(
        @record.target_snapshot,
        type: @record.target_type
      )
      @record.update!(
        status: "purged",
        purged_by: @actor,
        purged_at: @at,
        purge_reason: @reason,
        target_snapshot: snapshot,
        blocker_codes: [],
        last_evaluated_at: @at,
        purge_attempts: @record.purge_attempts + 1
      )
      Administration::AuditLogger.call(
        actor: @actor,
        action: "data_governance.content_purged",
        request_id: @request_id,
        reason: @reason,
        before_state: snapshot,
        after_state: { purged_at: @at.iso8601 },
        metadata: {
          lifecycle_public_id: @record.public_id,
          target_type: @record.target_type,
          target_id: @record.target_id,
          target_missing: true,
          scheduled: @actor.nil?
        }
      )
    end

    def audit_blocked_attempt(target, blockers)
      return unless @actor

      Administration::AuditLogger.call(
        actor: @actor,
        action: "data_governance.content_purge_blocked",
        resource: target,
        request_id: @request_id,
        reason: @reason,
        metadata: {
          lifecycle_public_id: @record.public_id,
          blockers: blockers
        }
      )
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
