# frozen_string_literal: true

module Minecraft
  class PlanWorldRestore < ApplicationService
    EXPIRES_IN = 15.minutes
    REQUEST_ID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

    class << self
      def confirmation_for(plan)
        "RESTORE #{plan.server.public_id} #{plan.world_backup.public_id} #{plan.public_id.last(8).upcase}"
      end

      def server_configuration_snapshot(server, world_relative_path)
        {
          "server_id" => server.public_id,
          "node_id" => server.node&.public_id,
          "working_directory" => server.working_directory.to_s,
          "world_relative_path" => world_relative_path,
          "process_driver" => server.process_driver.to_s,
          "process_config" => server.process_config.to_h
        }
      end

      def server_configuration_digest(server, world_relative_path)
        Minecraft::NodeOperationDigest.call(server_configuration_snapshot(server, world_relative_path))
      end

      def current_contract_error(plan, actor:)
        return :world_restore_unauthorized unless actor&.id == plan.actor_id && actor.permission?("minecraft.world_restores.execute")

        server = plan.server.reload
        node = server.node
        backup = plan.world_backup.reload
        return :world_restore_plan_expired if plan.expires_at <= Time.current
        return :world_restore_server_must_be_stopped unless server.process_state_stopped?
        return :world_restore_node_changed unless node&.id == plan.node_id
        return :world_restore_backup_unavailable unless backup.restorable?
        return :world_restore_backup_changed unless backup.manifest_digest == plan.backup_manifest_digest
        return :world_restore_backup_wrong_target unless backup.server_id == server.id && backup.node_id == node.id
        return :world_restore_node_stale unless node.fresh_heartbeat?
        return :world_restore_node_capability_required unless node.supports_managed_world_backups_v2? && node.supports_world_restore_v2?
        return :world_restore_node_recovery_required if ActiveModel::Type::Boolean.new.cast(node.metadata["world_restore_recovery_required"])

        path_result = Minecraft::WorldPathPolicy.call(server.metadata["world_directory"].presence || "world")
        return path_result.code&.to_sym || :world_relative_path_invalid if path_result.failure?
        return :world_restore_configuration_changed unless path_result.value.fetch(:path) == plan.world_relative_path
        return :world_restore_backup_path_changed unless
          backup.manifest_summary.to_h["world_relative_path"] == plan.world_relative_path
        return :world_restore_configuration_changed unless
          server_configuration_digest(server, plan.world_relative_path) == plan.server_configuration_digest
        return :world_restore_capability_changed unless node.world_safety_capability_digest == plan.node_capability_digest

        nil
      end
    end

    def initialize(server:, backup:, actor:, reason:, request_id:)
      @server = server
      @backup = backup
      @actor = actor
      @reason = reason.to_s.strip
      @request_id = request_id.to_s.strip.downcase
    end

    def call
      return failure(:world_restore_unauthorized) unless @actor&.permission?("minecraft.world_restores.execute")
      return failure(:world_restore_request_id_invalid) unless @request_id.match?(REQUEST_ID_PATTERN)
      return failure(:world_restore_reason_required) if @reason.blank?
      return failure(:world_restore_reason_too_long) if @reason.length > 1_000

      request_digest = Minecraft::NodeOperationDigest.call(
        "actor_id" => @actor.id,
        "server_id" => @server.public_id,
        "backup_id" => @backup.public_id,
        "reason" => @reason
      )
      if (existing = Minecraft::WorldRestorePlan.find_by(request_id: @request_id))
        return idempotent_result(existing, request_digest)
      end

      plan = nil
      Minecraft::WorldRestorePlan.transaction do
        @server.lock!
        expire_stale_plans!

        validation = validate_initial_contract
        raise PlanError, validation.to_s if validation

        world_path = Minecraft::WorldPathPolicy.call(
          @server.metadata["world_directory"].presence || "world"
        ).value.fetch(:path)
        configuration_digest = self.class.server_configuration_digest(@server, world_path)
        capability_digest = @server.node.world_safety_capability_digest
        public_id = unique_public_id
        expires_at = Time.current + EXPIRES_IN
        plan_digest = Minecraft::NodeOperationDigest.call(
          "public_id" => public_id,
          "actor_id" => @actor.id,
          "server_id" => @server.public_id,
          "node_id" => @server.node.public_id,
          "backup_id" => @backup.public_id,
          "backup_manifest_digest" => @backup.manifest_digest,
          "reason" => @reason,
          "request_id" => @request_id,
          "server_configuration_digest" => configuration_digest,
          "node_capability_digest" => capability_digest,
          "world_relative_path" => world_path,
          "expires_at" => expires_at.utc.iso8601(6)
        )

        plan = Minecraft::WorldRestorePlan.create!(
          public_id: public_id,
          server: @server,
          node: @server.node,
          world_backup: @backup,
          actor: @actor,
          status: "planned",
          reason: @reason,
          request_id: @request_id,
          request_digest: request_digest,
          plan_digest: plan_digest,
          backup_manifest_digest: @backup.manifest_digest,
          server_configuration_digest: configuration_digest,
          node_capability_digest: capability_digest,
          frozen_server_updated_at: @server.updated_at,
          world_relative_path: world_path,
          expires_at: expires_at
        )
        append_event(plan, "minecraft.world_restore.planned", "planned", actor: @actor)
        AuditLog.record!(
          action: "minecraft.world_restore.planned",
          actor: @actor,
          resource: plan,
          reason: @reason,
          request_id: @request_id,
          metadata: audit_metadata(plan)
        )
      end

      ServiceResult.success(plan: plan, confirmation: self.class.confirmation_for(plan), idempotent: false)
    rescue PlanError => error
      failure(error.message.to_sym)
    rescue ActiveRecord::RecordNotUnique
      existing = Minecraft::WorldRestorePlan.find_by(request_id: @request_id)
      return idempotent_result(existing, request_digest) if existing

      failure(:world_restore_active)
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end

    private

    class PlanError < StandardError; end

    def validate_initial_contract
      return :world_restore_node_required unless @server.node
      return :world_restore_server_must_be_stopped unless @server.process_state_stopped?
      return :world_restore_node_stale unless @server.node.fresh_heartbeat?
      return :world_restore_node_capability_required unless
        @server.node.supports_managed_world_backups_v2? && @server.node.supports_world_restore_v2?
      return :world_restore_node_recovery_required if
        ActiveModel::Type::Boolean.new.cast(@server.node.metadata["world_restore_recovery_required"])
      return :world_restore_backup_unavailable unless @backup&.restorable?
      return :world_restore_backup_wrong_target unless
        @backup.server_id == @server.id && @backup.node_id == @server.node.id
      return :world_restore_active if @server.world_restore_plans.active.exists?

      path_result = Minecraft::WorldPathPolicy.call(@server.metadata["world_directory"].presence || "world")
      return path_result.code&.to_sym || :world_relative_path_invalid if path_result.failure?
      return :world_restore_backup_path_changed unless
        @backup.manifest_summary.to_h["world_relative_path"] == path_result.value.fetch(:path)

      nil
    end

    def expire_stale_plans!
      @server.world_restore_plans
        .where(status: %w[planned authorized])
        .where("expires_at <= ?", Time.current)
        .lock
        .find_each do |plan|
          plan.update!(status: "expired", failed_at: Time.current, error_code: "world_restore_plan_expired")
          append_event(plan, "minecraft.world_restore.expired", "expired")
          AuditLog.record!(
            action: "minecraft.world_restore.expired",
            resource: plan,
            reason: plan.reason,
            request_id: plan.request_id,
            metadata: audit_metadata(plan)
          )
        end
    end

    def unique_public_id
      loop do
        value = SecureRandom.urlsafe_base64(12)
        return value unless Minecraft::WorldRestorePlan.exists?(public_id: value)
      end
    end

    def idempotent_result(existing, request_digest)
      return failure(:world_restore_idempotency_conflict) unless
        existing&.actor_id == @actor&.id && existing.request_digest == request_digest

      ServiceResult.success(
        plan: existing,
        confirmation: self.class.confirmation_for(existing),
        idempotent: true
      )
    end

    def append_event(plan, event_type, phase, actor: nil)
      result = Minecraft::AppendWorldRestoreEvent.call(
        plan: plan,
        event_type: event_type,
        phase: phase,
        actor: actor,
        payload: audit_metadata(plan)
      )
      raise PlanError, "world_restore_event_ledger_failed" if result.failure?
    end

    def audit_metadata(plan)
      {
        request_id: plan.request_id,
        server_id: plan.server.public_id,
        backup_id: plan.world_backup.public_id,
        plan_id: plan.public_id,
        plan_digest: plan.plan_digest.first(12),
        manifest_digest: plan.backup_manifest_digest.first(12),
        status: plan.status
      }
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
