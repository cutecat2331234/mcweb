# frozen_string_literal: true

module Minecraft
  class PlanWorldRestoreRecovery < ApplicationService
    REQUEST_ID_PATTERN = PlanWorldRestore::REQUEST_ID_PATTERN
    PERMISSION = "minecraft.world_restores.resolve_recovery"
    EXPIRES_IN = 10.minutes

    class << self
      def confirmation_for(resolution)
        plan = resolution.restore_plan
        "RESOLVE #{plan.server.public_id} #{plan.public_id.last(8).upcase} #{resolution.resolution_action.upcase}"
      end

      def current_contract_error(plan, actor:, server:, node:, action:)
        return :world_restore_recovery_unauthorized unless actor&.permission?(PERMISSION)
        return :world_restore_recovery_not_required unless plan.status_recovery_required?
        return :world_restore_server_must_be_stopped unless server.process_state_stopped?
        return :world_restore_node_changed unless node&.id == plan.node_id
        return :world_restore_node_stale unless node.fresh_heartbeat?
        return :world_restore_recovery_capability_required unless node.supports_world_restore_recovery_v2?
        node_requires_recovery = ActiveModel::Type::Boolean.new.cast(
          node.metadata["world_restore_recovery_required"]
        )
        return :world_restore_recovery_not_confirmed_by_node if
          action.to_s != "reconcile" && !node_requires_recovery

        path_result = Minecraft::WorldPathPolicy.call(server.metadata["world_directory"].presence || "world")
        return path_result.code&.to_sym || :world_relative_path_invalid if path_result.failure?
        return :world_restore_configuration_changed unless path_result.value.fetch(:path) == plan.world_relative_path
        return :world_restore_configuration_changed unless
          Minecraft::PlanWorldRestore.server_configuration_digest(server, plan.world_relative_path) ==
            plan.server_configuration_digest
        return :world_restore_backup_wrong_target unless
          plan.world_backup.server_id == server.id && plan.world_backup.node_id == node.id
        nil
      end
    end

    def initialize(plan:, actor:, resolution_action:, reason:, request_id:, expected_plan_lock_version:)
      @plan = plan
      @actor = actor
      @resolution_action = resolution_action.to_s
      @reason = reason.to_s.strip
      @request_id = request_id.to_s.strip.downcase
      @expected_plan_lock_version = Integer(expected_plan_lock_version, exception: false)
    end

    def call
      return failure(:world_restore_recovery_unauthorized) unless @actor&.permission?(PERMISSION)
      return failure(:world_restore_recovery_action_invalid) unless Minecraft::WorldRestoreResolution::ACTIONS.include?(@resolution_action)
      return failure(:world_restore_recovery_reason_required) if @reason.blank?
      return failure(:world_restore_recovery_reason_too_long) if @reason.length > 1_000
      return failure(:world_restore_recovery_request_id_invalid) unless @request_id.match?(REQUEST_ID_PATTERN)
      return failure(:world_restore_recovery_lock_version_required) if @expected_plan_lock_version.nil? || @expected_plan_lock_version.negative?

      request_digest = Minecraft::NodeOperationDigest.call(
        "actor_id" => @actor.id,
        "plan_id" => @plan.public_id,
        "resolution_action" => @resolution_action,
        "reason" => @reason,
        "expected_plan_lock_version" => @expected_plan_lock_version
      )
      if (existing = Minecraft::WorldRestoreResolution.find_by(request_id: @request_id))
        return idempotent_result(existing, request_digest)
      end

      resolution = nil
      Minecraft::WorldRestorePlan.transaction do
        @plan.lock!
        server = Minecraft::Server.lock.find(@plan.server_id)
        node = Minecraft::Node.lock.find(@plan.node_id)
        server.association(:node).target = node
        @plan.association(:server).target = server
        @plan.association(:node).target = node
        @plan.association(:world_backup).target = Minecraft::WorldBackup.lock.find(@plan.minecraft_world_backup_id)
        if @plan.pre_restore_world_backup_id
          @plan.association(:pre_restore_world_backup).target = Minecraft::WorldBackup.lock.find(
            @plan.pre_restore_world_backup_id
          )
        end

        @plan.recovery_resolutions.expirable
          .where("expires_at <= ?", Time.current)
          .order(:id)
          .lock
          .each { |candidate| Minecraft::ExpireWorldRestoreRecoveryResolution.expire_locked!(candidate) }

        raise RecoveryPlanError, "world_restore_recovery_stale" unless @plan.lock_version == @expected_plan_lock_version
        if (error = self.class.current_contract_error(
          @plan,
          actor: @actor,
          server: server,
          node: node,
          action: @resolution_action
        ))
          raise RecoveryPlanError, error.to_s
        end
        raise RecoveryPlanError, "world_restore_recovery_active" if @plan.recovery_resolutions.active.exists?

        resolution = @plan.recovery_resolutions.create!(
          actor: @actor,
          status: "planned",
          resolution_action: @resolution_action,
          reason: @reason,
          request_id: @request_id,
          request_digest: request_digest,
          expected_plan_lock_version: @expected_plan_lock_version,
          plan_digest: @plan.plan_digest,
          server_configuration_digest: @plan.server_configuration_digest,
          node_capability_digest: node.world_recovery_capability_digest,
          pre_restore_manifest_digest: @plan.pre_restore_world_backup&.manifest_digest,
          expires_at: Time.current + EXPIRES_IN
        )
        append_event!(
          resolution,
          "minecraft.world_restore.recovery_resolution_planned",
          resolution_id: resolution.public_id,
          resolution_action: resolution.resolution_action
        )
        audit!("minecraft.world_restore.recovery_resolution_planned", resolution)
      end

      ServiceResult.success(
        resolution: resolution,
        confirmation: self.class.confirmation_for(resolution),
        idempotent: false
      )
    rescue RecoveryPlanError => error
      failure(error.message.to_sym)
    rescue ActiveRecord::RecordNotUnique
      existing = Minecraft::WorldRestoreResolution.find_by(request_id: @request_id)
      return idempotent_result(existing, request_digest) if existing

      failure(:world_restore_recovery_active)
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    rescue Minecraft::ExpireWorldRestoreRecoveryResolution::ExpirationError => error
      failure(error.message.to_sym)
    end

    private

    class RecoveryPlanError < StandardError; end

    def idempotent_result(existing, request_digest)
      return failure(:world_restore_recovery_idempotency_conflict) unless
        existing&.actor_id == @actor&.id &&
          existing.minecraft_world_restore_plan_id == @plan.id &&
          existing.request_digest == request_digest

      ServiceResult.success(
        resolution: existing,
        confirmation: self.class.confirmation_for(existing),
        idempotent: true
      )
    end

    def append_event!(resolution, event_type, payload = {})
      result = Minecraft::AppendWorldRestoreEvent.call(
        plan: @plan,
        event_type: event_type,
        phase: "recovery_required",
        actor: @actor,
        payload: audit_metadata(resolution).merge(payload)
      )
      raise RecoveryPlanError, "world_restore_event_ledger_failed" if result.failure?
    end

    def audit!(action, resolution)
      AuditLog.record!(
        action: action,
        actor: @actor,
        resource: @plan,
        reason: resolution.reason,
        request_id: resolution.request_id,
        metadata: audit_metadata(resolution)
      )
    end

    def audit_metadata(resolution)
      {
        plan_id: @plan.public_id,
        server_id: @plan.server.public_id,
        resolution_id: resolution.public_id,
        resolution_action: resolution.resolution_action,
        resolution_status: resolution.status,
        expected_plan_lock_version: resolution.expected_plan_lock_version
      }
    end

    def failure(code)
      ServiceResult.failure(error: code.to_s, code: code.to_s)
    end
  end
end
