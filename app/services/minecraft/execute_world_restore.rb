# frozen_string_literal: true

module Minecraft
  class ExecuteWorldRestore < ApplicationService
    IDEMPOTENT_EXECUTION_STATUSES = %w[
      queued running completed failed rolled_back recovery_required
    ].freeze

    def initialize(plan:, actor:, authorization_token:, confirmation:)
      @plan = plan
      @actor = actor
      @authorization_token = authorization_token.to_s
      @confirmation = confirmation.to_s.strip
    end

    def call
      return failure(:world_restore_unauthorized) unless
        @actor&.id == @plan.actor_id && @actor.permission?("minecraft.world_restores.execute")

      result = nil
      Minecraft::WorldRestorePlan.transaction do
        @plan.lock!
        unless secure_match?(@confirmation, Minecraft::PlanWorldRestore.confirmation_for(@plan))
          result = failure(:world_restore_confirmation_mismatch)
          next
        end
        if IDEMPOTENT_EXECUTION_STATUSES.include?(@plan.status)
          unless secure_match?(
            Digest::SHA256.hexdigest(@authorization_token),
            @plan.authorization_digest.to_s
          ) && @plan.authorization_consumed_at.present? && @plan.node_operation.present?
            result = failure(:world_restore_authorization_invalid)
            next
          end
          result = ServiceResult.success(
            plan: @plan,
            operation: @plan.node_operation,
            idempotent: true
          )
          next
        end
        unless @plan.status_authorized?
          result = failure(:world_restore_plan_not_authorized)
          next
        end
        if @plan.authorization_expires_at.blank? || @plan.authorization_expires_at <= Time.current
          result = failure(:world_restore_authorization_expired)
          next
        end

        verification = Minecraft::AuthorizeWorldRestore.verify(
          @authorization_token,
          plan: @plan,
          actor: @actor
        )
        if verification.failure?
          result = verification
          next
        end
        if (error = Minecraft::PlanWorldRestore.current_contract_error(@plan, actor: @actor))
          result = failure(error)
          next
        end

        pre_restore_backup = create_pre_restore_backup!
        operation_result = Minecraft::EnqueueNodeOperation.call(
          operation_type: "world_restore_execute",
          servers: [ @plan.server ],
          payload: {
            protocol_version: 2,
            plan_id: @plan.public_id,
            plan_digest: @plan.plan_digest,
            node_id: @plan.node.public_id,
            backup_id: @plan.world_backup.public_id,
            backup_manifest_digest: @plan.backup_manifest_digest,
            pre_restore_backup_id: pre_restore_backup.public_id,
            world_relative_path: @plan.world_relative_path,
            server_configuration_digest: @plan.server_configuration_digest,
            safety_profile: Minecraft::WorldBackupManifest::SAFETY_PROFILE,
            expected_process_state: "stopped"
          },
          idempotency_key: "world-restore:#{@plan.public_id}"
        )
        if operation_result.failure?
          raise ExecutionError, (operation_result.code.presence || "world_restore_enqueue_failed")
        end

        operation = operation_result.value.fetch(:operation)
        pre_restore_backup.update!(status: "queued", node_operation: operation)
        @plan.update!(
          status: "queued",
          pre_restore_world_backup: pre_restore_backup,
          node_operation: operation,
          authorization_consumed_at: Time.current,
          queued_at: Time.current
        )
        append_event("minecraft.world_restore.queued", "queued", pre_restore_backup_id: pre_restore_backup.public_id)
        AuditLog.record!(
          action: "minecraft.world_restore.queued",
          actor: @actor,
          resource: @plan,
          reason: @plan.reason,
          request_id: @plan.request_id,
          metadata: safe_metadata.merge(pre_restore_backup_id: pre_restore_backup.public_id)
        )
        result = ServiceResult.success(plan: @plan, operation: operation, idempotent: false)
      end
      result || failure(:world_restore_enqueue_failed)
    rescue ActiveRecord::RecordNotUnique
      @plan.reload
      return ServiceResult.success(plan: @plan, operation: @plan.node_operation, idempotent: true) if @plan.node_operation

      failure(:world_restore_idempotency_conflict)
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    rescue ExecutionError => error
      failure(error.message.to_sym)
    end

    private

    class ExecutionError < StandardError; end

    def create_pre_restore_backup!
      request_id = deterministic_uuid("pre-restore:#{@plan.public_id}")
      existing = Minecraft::WorldBackup.find_by(request_id: request_id)
      return existing if existing&.request_digest == @plan.plan_digest
      raise ActiveRecord::RecordNotUnique if existing

      Minecraft::WorldBackup.create!(
        server: @plan.server,
        node: @plan.node,
        created_by: @actor,
        purpose: "pre_restore",
        status: "requested",
        request_id: request_id,
        request_digest: @plan.plan_digest
      )
    end

    def deterministic_uuid(value)
      hex = Digest::SHA256.hexdigest(value).first(32)
      [ hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12] ].join("-")
    end

    def append_event(event_type, phase, payload = {})
      result = Minecraft::AppendWorldRestoreEvent.call(
        plan: @plan,
        event_type: event_type,
        phase: phase,
        actor: @actor,
        payload: safe_metadata.merge(payload)
      )
      raise ExecutionError, "world_restore_event_ledger_failed" if result.failure?
    end

    def safe_metadata
      {
        plan_id: @plan.public_id,
        server_id: @plan.server.public_id,
        backup_id: @plan.world_backup.public_id,
        request_id: @plan.request_id,
        status: @plan.status
      }
    end

    def secure_match?(left, right)
      left.bytesize == right.to_s.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(left, right.to_s)
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
