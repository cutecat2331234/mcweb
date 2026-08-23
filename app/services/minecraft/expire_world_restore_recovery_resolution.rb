# frozen_string_literal: true

module Minecraft
  class ExpireWorldRestoreRecoveryResolution < ApplicationService
    class << self
      def expire_locked!(
        resolution,
        now: Time.current,
        force: false,
        error_code: "world_restore_recovery_resolution_expired"
      )
        return false unless force || resolution.expired_by_time?(now)
        return false unless resolution.status.in?(%w[planned authorized])

        plan = resolution.restore_plan
        resolution.update!(
          status: "expired",
          expired_at: now,
          error_code: error_code
        )
        event = Minecraft::AppendWorldRestoreEvent.call(
          plan: plan,
          event_type: "minecraft.world_restore.recovery_resolution_expired",
          phase: "recovery_required",
          payload: metadata(resolution)
        )
        raise ExpirationError, "world_restore_event_ledger_failed" if event.failure?

        AuditLog.record!(
          action: "minecraft.world_restore.recovery_resolution_expired",
          resource: plan,
          reason: resolution.reason,
          request_id: resolution.request_id,
          metadata: metadata(resolution)
        )
        true
      end

      private

      def metadata(resolution)
        {
          plan_id: resolution.restore_plan.public_id,
          server_id: resolution.restore_plan.server.public_id,
          resolution_id: resolution.public_id,
          resolution_action: resolution.resolution_action,
          resolution_status: resolution.status,
          expired_at: resolution.expired_at
        }
      end
    end

    def initialize(resolution:)
      @resolution = resolution
      @plan = resolution.restore_plan
    end

    def call
      changed = false
      Minecraft::WorldRestorePlan.transaction do
        @plan.lock!
        @resolution = @plan.recovery_resolutions.lock.find(@resolution.id)
        changed = self.class.expire_locked!(@resolution)
      end
      ServiceResult.success(resolution: @resolution, expired: changed)
    rescue ExpirationError => error
      ServiceResult.failure(error: error.message.to_sym, code: error.message.to_sym)
    end

    class ExpirationError < StandardError; end
  end
end
