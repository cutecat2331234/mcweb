# frozen_string_literal: true

module Minecraft
  class ExecuteWorldRestoreRecovery < ApplicationService
    IDEMPOTENT_STATUSES = %w[queued running completed failed recovery_required].freeze

    def initialize(resolution:, actor:, authorization_token:, confirmation:, expected_lock_version:)
      @resolution = resolution
      @plan = resolution.restore_plan
      @actor = actor
      @authorization_token = authorization_token.to_s
      @confirmation = confirmation.to_s.strip
      @expected_lock_version = Integer(expected_lock_version, exception: false)
    end

    def call
      return failure(:world_restore_recovery_unauthorized) unless @actor&.permission?(
        Minecraft::PlanWorldRestoreRecovery::PERMISSION
      ) && @resolution.actor_id == @actor.id
      return failure(:world_restore_recovery_lock_version_required) if @expected_lock_version.nil?

      result = nil
      Minecraft::WorldRestorePlan.transaction do
        @plan.lock!
        server = Minecraft::Server.lock.find(@plan.server_id)
        node = Minecraft::Node.lock.find(@plan.node_id)
        selected_backup = Minecraft::WorldBackup.lock.find(@plan.minecraft_world_backup_id)
        pre_restore_backup = if @plan.pre_restore_world_backup_id
          Minecraft::WorldBackup.lock.find(@plan.pre_restore_world_backup_id)
        end
        server.association(:node).target = node
        @plan.association(:server).target = server
        @plan.association(:node).target = node
        @plan.association(:world_backup).target = selected_backup
        @plan.association(:pre_restore_world_backup).target = pre_restore_backup
        @resolution = @plan.recovery_resolutions.lock.find(@resolution.id)

        now = Time.current
        authorization_expired = @resolution.status_authorized? && (
          @resolution.authorization_expires_at.blank? || @resolution.authorization_expires_at <= now
        )
        if @resolution.expired_by_time?(now) || authorization_expired
          Minecraft::ExpireWorldRestoreRecoveryResolution.expire_locked!(
            @resolution,
            now: now,
            force: authorization_expired,
            error_code: authorization_expired ?
              "world_restore_recovery_authorization_expired" :
              "world_restore_recovery_resolution_expired"
          )
          result = failure(
            authorization_expired ?
              :world_restore_recovery_authorization_expired :
              :world_restore_recovery_resolution_expired
          )
          next
        end
        unless secure_match?(
          @confirmation,
          Minecraft::PlanWorldRestoreRecovery.confirmation_for(@resolution)
        )
          result = failure(:world_restore_recovery_confirmation_mismatch)
          next
        end
        if IDEMPOTENT_STATUSES.include?(@resolution.status)
          unless secure_match?(
            Digest::SHA256.hexdigest(@authorization_token),
            @resolution.authorization_digest.to_s
          ) && @resolution.authorization_consumed_at.present? && @resolution.node_operation.present?
            result = failure(:world_restore_recovery_authorization_invalid)
            next
          end
          result = ServiceResult.success(
            resolution: @resolution,
            operation: @resolution.node_operation,
            idempotent: true
          )
          next
        end
        unless @resolution.status_authorized?
          result = failure(:world_restore_recovery_not_authorized)
          next
        end
        unless @resolution.lock_version == @expected_lock_version
          result = failure(:world_restore_recovery_stale)
          next
        end
        verification = Minecraft::AuthorizeWorldRestoreRecovery.verify(
          @authorization_token,
          resolution: @resolution,
          actor: @actor
        )
        if verification.failure?
          result = verification
          next
        end
        if (error = Minecraft::PlanWorldRestoreRecovery.current_contract_error(
          @plan,
          actor: @actor,
          server: server,
          node: node,
          action: @resolution.resolution_action
        ))
          result = failure(error)
          next
        end
        unless node.world_recovery_capability_digest == @resolution.node_capability_digest
          result = failure(:world_restore_recovery_capability_changed)
          next
        end
        unless @resolution.pre_restore_manifest_digest == pre_restore_backup&.manifest_digest
          result = failure(:world_restore_recovery_pre_snapshot_changed)
          next
        end

        operation_result = Minecraft::EnqueueNodeOperation.call(
          operation_type: "world_restore_reconcile",
          servers: [ server ],
          payload: {
            protocol_version: 2,
            resolution_id: @resolution.public_id,
            resolution_action: @resolution.resolution_action,
            reason_digest: Digest::SHA256.hexdigest(@resolution.reason),
            plan_id: @plan.public_id,
            plan_digest: @plan.plan_digest,
            node_id: node.public_id,
            backup_id: selected_backup.public_id,
            backup_manifest_digest: @plan.backup_manifest_digest,
            pre_restore_backup_id: pre_restore_backup&.public_id,
            pre_restore_manifest_digest: pre_restore_backup&.manifest_digest,
            world_relative_path: @plan.world_relative_path,
            server_configuration_digest: @plan.server_configuration_digest,
            recovery_capability_digest: @resolution.node_capability_digest,
            safety_profile: Minecraft::WorldBackupManifest::SAFETY_PROFILE,
            expected_process_state: "stopped"
          },
          idempotency_key: "world-restore-resolution:#{@resolution.public_id}"
        )
        if operation_result.failure?
          raise ExecutionError, (operation_result.code.presence || "world_restore_recovery_enqueue_failed")
        end

        operation = operation_result.value.fetch(:operation)
        @resolution.update!(
          status: "queued",
          node_operation: operation,
          authorization_consumed_at: Time.current,
          queued_at: Time.current
        )
        append_event!("minecraft.world_restore.recovery_resolution_queued", operation_id: operation.public_id)
        audit!("minecraft.world_restore.recovery_resolution_queued", operation_id: operation.public_id)
        result = ServiceResult.success(resolution: @resolution, operation: operation, idempotent: false)
      end
      result || failure(:world_restore_recovery_enqueue_failed)
    rescue ActiveRecord::RecordNotUnique
      @resolution.reload
      return ServiceResult.success(
        resolution: @resolution,
        operation: @resolution.node_operation,
        idempotent: true
      ) if @resolution.node_operation

      failure(:world_restore_recovery_idempotency_conflict)
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    rescue Minecraft::ExpireWorldRestoreRecoveryResolution::ExpirationError => error
      failure(error.message.to_sym)
    rescue ExecutionError => error
      failure(error.message.to_sym)
    end

    private

    class ExecutionError < StandardError; end

    def append_event!(event_type, payload = {})
      event = Minecraft::AppendWorldRestoreEvent.call(
        plan: @plan,
        event_type: event_type,
        phase: "recovery_required",
        actor: @actor,
        payload: audit_metadata.merge(payload)
      )
      raise ExecutionError, "world_restore_event_ledger_failed" if event.failure?
    end

    def audit!(action, payload = {})
      AuditLog.record!(
        action: action,
        actor: @actor,
        resource: @plan,
        reason: @resolution.reason,
        request_id: @resolution.request_id,
        metadata: audit_metadata.merge(payload)
      )
    end

    def audit_metadata
      {
        plan_id: @plan.public_id,
        server_id: @plan.server.public_id,
        resolution_id: @resolution.public_id,
        resolution_action: @resolution.resolution_action,
        resolution_status: @resolution.status
      }
    end

    def secure_match?(left, right)
      left = left.to_s
      right = right.to_s
      left.bytesize == right.bytesize && ActiveSupport::SecurityUtils.secure_compare(left, right)
    end

    def failure(code)
      ServiceResult.failure(error: code.to_s, code: code.to_s)
    end
  end
end
