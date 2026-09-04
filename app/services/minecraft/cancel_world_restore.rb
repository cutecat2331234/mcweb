# frozen_string_literal: true

module Minecraft
  class CancelWorldRestore < ApplicationService
    PERMISSION = "minecraft.world_restores.execute"

    def initialize(plan:, actor:, reason:, request_id:, expected_lock_version:)
      @plan = plan
      @actor = actor
      @reason = reason.to_s.strip
      @request_id = request_id.to_s.strip.downcase
      @expected_lock_version = Integer(expected_lock_version, exception: false)
    end

    def call
      return failure(:world_restore_unauthorized) unless
        @actor&.session_eligible? && @actor.id == @plan.actor_id && @actor.permission?(PERMISSION)
      return failure(:world_restore_cancel_reason_required) if @reason.blank?
      return failure(:world_restore_cancel_reason_too_long) if @reason.length > 1_000
      return failure(:world_restore_cancel_request_id_invalid) unless
        @request_id.match?(Minecraft::PlanWorldRestore::REQUEST_ID_PATTERN)
      return failure(:world_restore_cancel_lock_version_required) if @expected_lock_version.nil?

      request_digest = cancellation_digest
      result = nil
      Minecraft::WorldRestorePlan.transaction do
        @plan.lock!

        if @plan.status_cancelled?
          result = idempotent_result(request_digest)
          next
        end
        unless @plan.status.in?(%w[planned authorized])
          result = failure(:world_restore_plan_not_cancellable)
          next
        end

        now = Time.current
        if @plan.expires_at <= now
          expire_plan!(now)
          result = failure(:world_restore_plan_expired)
          next
        end
        if @plan.lock_version != @expected_lock_version
          result = failure(:world_restore_stale)
          next
        end

        cancellation = {
          "request_id" => @request_id,
          "request_digest" => request_digest,
          "actor_id" => @actor.public_id,
          "reason" => @reason,
          "cancelled_at" => now.utc.iso8601(6)
        }
        @plan.update!(
          status: "cancelled",
          result_summary: @plan.result_summary.to_h.merge("cancellation" => cancellation)
        )
        append_event!(
          "minecraft.world_restore.cancelled",
          "cancelled",
          cancellation: cancellation.except("request_digest")
        )
        AuditLog.record!(
          action: "minecraft.world_restore.cancelled",
          actor: @actor,
          resource: @plan,
          reason: @reason,
          request_id: @request_id,
          metadata: audit_metadata.merge(cancellation_digest: request_digest.first(12))
        )
        result = ServiceResult.success(plan: @plan, idempotent: false)
      end

      result || failure(:world_restore_plan_not_cancellable)
    rescue ActiveRecord::StaleObjectError
      failure(:world_restore_stale)
    rescue CancellationError => error
      failure(error.message.to_sym)
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end

    private

    class CancellationError < StandardError; end

    def cancellation_digest
      Minecraft::NodeOperationDigest.call(
        "actor_id" => @actor.id,
        "plan_id" => @plan.public_id,
        "reason" => @reason,
        "request_id" => @request_id
      )
    end

    def idempotent_result(request_digest)
      cancellation = @plan.result_summary.to_h["cancellation"].to_h
      return failure(:world_restore_idempotency_conflict) unless
        cancellation["request_id"] == @request_id &&
          cancellation["request_digest"] == request_digest

      ServiceResult.success(plan: @plan, idempotent: true)
    end

    def expire_plan!(now)
      @plan.update!(
        status: "expired",
        failed_at: now,
        error_code: "world_restore_plan_expired"
      )
      append_event!("minecraft.world_restore.expired", "expired")
      AuditLog.record!(
        action: "minecraft.world_restore.expired",
        actor: @actor,
        resource: @plan,
        reason: @plan.reason,
        request_id: @plan.request_id,
        metadata: audit_metadata
      )
    end

    def append_event!(event_type, phase, payload = {})
      result = Minecraft::AppendWorldRestoreEvent.call(
        plan: @plan,
        event_type: event_type,
        phase: phase,
        actor: @actor,
        payload: audit_metadata.merge(payload)
      )
      raise CancellationError, "world_restore_event_ledger_failed" if result.failure?
    end

    def audit_metadata
      {
        plan_id: @plan.public_id,
        server_id: @plan.server.public_id,
        backup_id: @plan.world_backup.public_id,
        status: @plan.status
      }
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
