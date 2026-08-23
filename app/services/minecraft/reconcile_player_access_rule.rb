# frozen_string_literal: true

module Minecraft
  class ReconcilePlayerAccessRule < ApplicationService
    def initialize(task:, now: Time.current)
      @task = task
      @now = now
    end

    def call
      rule = Minecraft::PlayerAccessRule.find_by(apply_task_id: @task.id) ||
        Minecraft::PlayerAccessRule.find_by(revoke_task_id: @task.id)
      return ServiceResult.success(rule: nil, changed: false) unless rule
      return ServiceResult.success(rule: rule, changed: false) unless @task.completed? || @task.failed?

      changed = false
      before_state = nil
      rule.with_lock do
        before_state = state(rule)
        if rule.apply_task_id == @task.id
          changed = reconcile_apply(rule)
        elsif rule.revoke_task_id == @task.id
          changed = reconcile_revoke(rule)
        end
      end
      audit(rule, before_state:) if changed
      Minecraft::ExpirePlayerAccessRulesJob.perform_later if changed && rule.active? && rule.expires_at&.past?
      ServiceResult.success(rule: rule, changed: changed)
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash, code: :minecraft_access_rule_reconcile_failed)
    end

    private

    def reconcile_apply(rule)
      return false unless rule.pending_apply?

      if @task.completed?
        rule.update!(status: "active", applied_at: @now, failed_at: nil)
      else
        rule.update!(status: "failed", failed_at: @now)
      end
      true
    end

    def reconcile_revoke(rule)
      return false unless rule.pending_revoke?

      if @task.completed?
        rule.update!(status: "revoked", revoked_at: @now, failed_at: nil)
      else
        rule.update!(status: "active", failed_at: @now)
      end
      true
    end

    def state(rule)
      {
        status: rule.status,
        applied_at: rule.applied_at&.iso8601,
        revoked_at: rule.revoked_at&.iso8601,
        failed_at: rule.failed_at&.iso8601
      }
    end

    def audit(rule, before_state:)
      action = if rule.revoked?
                 "minecraft.player_access_rule.revoked"
      elsif rule.active?
                 rule.revoke_task_id == @task.id ?
                   "minecraft.player_access_rule.revoke_delivery_failed" :
                   "minecraft.player_access_rule.applied"
      else
                 "minecraft.player_access_rule.apply_delivery_failed"
      end
      Administration::AuditLogger.call(
        actor: rule.revoked_by || rule.created_by,
        action: action,
        resource: rule,
        before_state: before_state,
        after_state: state(rule),
        reason: rule.revoke_reason.presence || rule.reason,
        metadata: {
          server_id: rule.server.public_id,
          connector_task_id: @task.id,
          connector_task_status: @task.status
        }
      )
    end
  end
end
