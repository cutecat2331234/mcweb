# frozen_string_literal: true

module Minecraft
  class DecidePrimaryAccountChangeRequest < ApplicationService
    ACTIONS = %w[approve reject].freeze

    def initialize(request_record:, actor:, action:, reason:, lock_version:, idempotency_key:)
      @request_record = request_record
      @actor = actor
      @action = action.to_s
      @reason = reason.to_s.strip
      @lock_version = Integer(lock_version, exception: false)
      @idempotency_key = idempotency_key.to_s
    end

    def call
      return failure(:primary_account_forbidden) unless @actor&.permission?("minecraft.primary_accounts.review")
      return failure(:primary_account_decision_invalid) unless @action.in?(ACTIONS)
      return failure(:primary_account_lock_version_required) unless @lock_version
      return failure(:primary_account_idempotency_required) if @idempotency_key.blank?
      return failure(:primary_account_reason_required) if @action == "reject" && @reason.blank?
      return failure(:primary_account_reason_too_long) if @reason.length > 2_000

      changed = false
      result = nil
      @request_record.user.with_lock do
        @request_record.lock!

        replay_status = @action == "approve" ? "approved" : "rejected"
        if @request_record.status == replay_status
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
        if @request_record.past_deadline?
          expire_locked_request
          changed = true
          result = failure(:primary_account_request_expired)
          next
        end

        if @action == "reject"
          @request_record.update!(
            status: "rejected",
            decided_by: @actor,
            decision_reason: @reason,
            resolved_at: Time.current
          )
          audit_resolution("minecraft.primary_account_change_rejected")
          changed = true
          result = ServiceResult.success(request: @request_record, replayed: false)
          next
        end

        unless target_and_source_still_valid?
          cancel_stale_request
          changed = true
          result = failure(:primary_account_request_accounts_changed)
          next
        end

        apply_result = Minecraft::ApplyPrimaryAccountChange.call(
          user: @request_record.user,
          target_identity_link: @request_record.target_identity_link,
          actor: @actor,
          change_source: "staff_approval",
          idempotency_key: "#{@idempotency_key}:request:#{@request_record.id}",
          reason: @request_record.request_reason,
          request_record: @request_record,
          enforce_cooldown: true,
          counts_for_cooldown: true
        )
        unless apply_result.success?
          result = apply_result
          next
        end

        now = Time.current
        @request_record.update!(
          status: "approved",
          decided_by: @actor,
          decision_reason: @reason.presence,
          resolved_at: now,
          applied_at: now
        )
        audit_resolution("minecraft.primary_account_change_approved")
        changed = true
        result = ServiceResult.success(
          request: @request_record,
          event: apply_result.value.fetch(:event),
          replayed: false
        )
      end

      Minecraft::PrimaryAccountNotifications.request_resolved(@request_record) if changed
      result
    rescue ActiveRecord::StaleObjectError
      failure(:primary_account_request_stale)
    end

    private

    def target_and_source_still_valid?
      target = @request_record.target_identity_link
      source = @request_record.source_identity_link
      target.user_id == @request_record.user_id && target.unlinked_at.nil? &&
        source&.user_id == @request_record.user_id && source&.unlinked_at.nil? && source&.primary_account?
    end

    def expire_locked_request
      @request_record.update!(
        status: "expired",
        resolved_at: Time.current,
        decision_reason: "request_expired"
      )
      audit_resolution("minecraft.primary_account_change_expired")
    end

    def cancel_stale_request
      @request_record.update!(
        status: "cancelled",
        decided_by: @actor,
        decision_reason: "identity_links_changed",
        resolved_at: Time.current
      )
      audit_resolution("minecraft.primary_account_change_cancelled")
    end

    def audit_resolution(action)
      Administration::AuditLogger.call(
        actor: @actor,
        action: action,
        resource: @request_record,
        request_id: @idempotency_key.first(100),
        reason: @reason.presence,
        metadata: {
          user_id: @request_record.user_id,
          source_identity_link_id: @request_record.source_identity_link_id,
          target_identity_link_id: @request_record.target_identity_link_id
        }
      )
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
