# frozen_string_literal: true

module Minecraft
  class CreateWorldBackup < ApplicationService
    REQUEST_ID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

    def initialize(server:, request_id:, purpose: "manual", actor: nil)
      @server = server
      @request_id = request_id.to_s.strip.downcase
      @purpose = purpose.to_s
      @actor = actor
    end

    def call
      return failure(:world_backup_unauthorized) if @actor && !@actor.permission?("minecraft.world_backups.manage")
      return failure(:world_backup_request_id_invalid) unless @request_id.match?(REQUEST_ID_PATTERN)
      return failure(:world_backup_purpose_invalid) unless Minecraft::WorldBackup::PURPOSES.include?(@purpose)

      result = nil
      request_digest = nil
      Minecraft::WorldBackup.transaction do
        @server.lock!
        unless @server.node
          result = failure(:world_backup_node_required)
          next
        end

        path_result = Minecraft::WorldPathPolicy.call(
          @server.metadata["world_directory"].presence || "world"
        )
        if path_result.failure?
          result = path_result
          next
        end
        world_path = path_result.value.fetch(:path)
        request_digest = Minecraft::NodeOperationDigest.call(
          "server_id" => @server.public_id,
          "node_id" => @server.node.public_id,
          "purpose" => @purpose,
          "world_relative_path" => world_path
        )

        backup = Minecraft::WorldBackup.find_by(request_id: @request_id)
        if backup && backup.request_digest != request_digest
          result = failure(:world_backup_idempotency_conflict)
          next
        end
        if backup && !backup.status_requested?
          result = idempotent_result(backup, request_digest)
          next
        end
        backup ||= Minecraft::WorldBackup.create!(
          server: @server,
          node: @server.node,
          created_by: @actor,
          purpose: @purpose,
          status: "requested",
          request_id: @request_id,
          request_digest: request_digest
        )

        eligibility_error = backup_eligibility_error
        if eligibility_error
          result = fail_backup(backup, eligibility_error)
          next
        end

        operation_result = Minecraft::EnqueueNodeOperation.call(
          operation_type: "world_backup_create",
          servers: [ @server ],
          payload: {
            protocol_version: 2,
            backup_id: backup.public_id,
            node_id: @server.node.public_id,
            purpose: @purpose,
            request_digest: request_digest,
            world_relative_path: world_path,
            safety_profile: Minecraft::WorldBackupManifest::SAFETY_PROFILE
          },
          idempotency_key: "world-backup:#{@request_id}"
        )
        if operation_result.failure?
          result = fail_backup(backup, operation_result.code || :world_backup_enqueue_failed)
          next
        end

        operation = operation_result.value.fetch(:operation)
        backup.update!(status: "queued", node_operation: operation)
        record_audit("minecraft.world_backup.requested", backup, request_id: @request_id, purpose: @purpose)
        result = ServiceResult.success(backup: backup, operation: operation, idempotent: false)
      end
      result || failure(:world_backup_enqueue_failed)
    rescue ActiveRecord::RecordNotUnique
      existing = Minecraft::WorldBackup.find_by(request_id: @request_id)
      return idempotent_result(existing, request_digest) if existing

      raise
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end

    private

    def backup_eligibility_error
      return :world_backup_server_must_be_stopped unless @server.process_state_stopped?
      return :world_backup_restore_active if @server.world_restore_plans.active.exists?
      return :world_backup_node_stale unless @server.node.fresh_heartbeat?
      return :world_backup_node_capability_required unless @server.node.supports_managed_world_backups_v2?
      return :world_backup_node_recovery_required if ActiveModel::Type::Boolean.new.cast(
        @server.node.metadata["world_restore_recovery_required"]
      )

      nil
    end

    def idempotent_result(existing, request_digest)
      return failure(:world_backup_idempotency_conflict) unless existing&.request_digest == request_digest
      return failure(existing.error_code.presence || :world_backup_failed, backup: existing) if existing.status_failed?
      return failure(:world_backup_quarantined, backup: existing) if existing.status_quarantined?

      ServiceResult.success(backup: existing, operation: existing.node_operation, idempotent: true)
    end

    def fail_backup(backup, code)
      backup.update!(status: "failed", failed_at: Time.current, error_code: code.to_s)
      record_audit("minecraft.world_backup.failed", backup, request_id: @request_id, error_code: code.to_s)
      failure(code, backup: backup)
    end

    def record_audit(action, backup, metadata)
      AuditLog.record!(
        action: action,
        actor: @actor,
        resource: backup,
        metadata: metadata,
        request_id: @request_id
      )
    end

    def failure(code, backup: nil)
      ServiceResult.failure(error: code, code: code, value: { backup: backup }.compact)
    end
  end
end
