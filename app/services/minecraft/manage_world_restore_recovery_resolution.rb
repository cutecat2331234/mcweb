# frozen_string_literal: true

module Minecraft
  class ManageWorldRestoreRecoveryResolution < ApplicationService
    ACTIONS = %w[cancel takeover].freeze
    RATE_LIMIT_SCOPE = "minecraft_world_restore_recovery_lifecycle"

    def initialize(
      resolution:,
      actor:,
      lifecycle_action:,
      reason:,
      request_id:,
      expected_plan_lock_version:,
      expected_resolution_lock_version:,
      password:,
      code: nil,
      ip_address: nil,
      resolution_action: nil
    )
      @resolution = resolution
      @plan = resolution.restore_plan
      @actor = actor
      @lifecycle_action = lifecycle_action.to_s
      @reason = reason.to_s.strip
      @request_id = request_id.to_s.strip.downcase
      @expected_plan_lock_version = Integer(expected_plan_lock_version, exception: false)
      @expected_resolution_lock_version = Integer(expected_resolution_lock_version, exception: false)
      @password = password
      @code = code
      @ip_address = ip_address
      @resolution_action = resolution_action.to_s
    end

    def call
      return failure(:world_restore_recovery_unauthorized) unless
        @actor&.session_eligible? && @actor.permission?(Minecraft::PlanWorldRestoreRecovery::PERMISSION)
      return failure(:world_restore_recovery_lifecycle_action_invalid) unless ACTIONS.include?(@lifecycle_action)
      return failure(:world_restore_recovery_reason_required) if @reason.blank?
      return failure(:world_restore_recovery_reason_too_long) if @reason.length > 1_000
      return failure(:world_restore_recovery_request_id_invalid) unless
        @request_id.match?(Minecraft::PlanWorldRestore::REQUEST_ID_PATTERN)
      return failure(:world_restore_recovery_lock_version_required) if
        @expected_plan_lock_version.nil? || @expected_resolution_lock_version.nil?
      return failure(:world_restore_recovery_action_invalid) if
        @lifecycle_action == "takeover" &&
          !Minecraft::WorldRestoreResolution::ACTIONS.include?(@resolution_action)

      digest = lifecycle_digest
      if (existing = Minecraft::WorldRestoreResolution.find_by(lifecycle_request_id: @request_id))
        return idempotent_result(existing, digest)
      end

      verification = verify_step_up
      return verification if verification.failure?
      method = verification.value.fetch(:authorization_method)
      authorized_at = verification.value.fetch(:authorized_at)

      replacement = nil
      idempotent = nil
      committed_failure = nil
      Minecraft::WorldRestorePlan.transaction do
        @plan.lock!
        server = Minecraft::Server.lock.find(@plan.server_id)
        node = Minecraft::Node.lock.find(@plan.node_id)
        selected_backup = Minecraft::WorldBackup.lock.find(@plan.minecraft_world_backup_id)
        pre_restore_backup = if @plan.pre_restore_world_backup_id
          Minecraft::WorldBackup.lock.find(@plan.pre_restore_world_backup_id)
        end
        @resolution = @plan.recovery_resolutions.lock.find(@resolution.id)
        bind_locked_associations(server, node, selected_backup, pre_restore_backup)

        if @resolution.lifecycle_request_id.present?
          idempotent = idempotent_result(@resolution, digest)
          next
        end
        raise LifecycleError, "world_restore_recovery_stale" unless
          @plan.lock_version == @expected_plan_lock_version &&
            @resolution.lock_version == @expected_resolution_lock_version
        if @resolution.expired_by_time?
          Minecraft::ExpireWorldRestoreRecoveryResolution.expire_locked!(@resolution)
          committed_failure = :world_restore_recovery_resolution_expired
          next
        end
        raise LifecycleError, "world_restore_recovery_lifecycle_not_allowed" unless
          @resolution.status.in?(%w[planned authorized])
        raise LifecycleError, "world_restore_recovery_not_required" unless @plan.status_recovery_required?

        if @lifecycle_action == "takeover"
          if (error = Minecraft::PlanWorldRestoreRecovery.current_contract_error(
            @plan,
            actor: @actor,
            server: server,
            node: node,
            action: @resolution_action
          ))
            raise LifecycleError, error.to_s
          end
          raise LifecycleError, "world_restore_recovery_capability_changed" unless
            node.world_recovery_capability_digest == @resolution.node_capability_digest
        end

        lifecycle_attributes = {
          status: @lifecycle_action == "cancel" ? "cancelled" : "taken_over",
          lifecycle_action: @lifecycle_action,
          lifecycle_actor: @actor,
          lifecycle_reason: @reason,
          lifecycle_request_id: @request_id,
          lifecycle_request_digest: digest,
          lifecycle_authorization_method: method,
          lifecycle_authorized_at: authorized_at,
          lifecycle_completed_at: Time.current
        }
        @resolution.update!(lifecycle_attributes)

        if @lifecycle_action == "takeover"
          replacement = create_replacement!(node)
          append_event!(
            "minecraft.world_restore.recovery_resolution_taken_over",
            @resolution,
            prior_actor_id: @resolution.actor.public_id,
            replacement_resolution_id: replacement.public_id
          )
          append_event!(
            "minecraft.world_restore.recovery_resolution_planned",
            replacement,
            supersedes_resolution_id: @resolution.public_id
          )
          audit!("minecraft.world_restore.recovery_resolution_taken_over", @resolution,
            replacement_resolution_id: replacement.public_id)
          audit!("minecraft.world_restore.recovery_resolution_planned", replacement,
            supersedes_resolution_id: @resolution.public_id)
        else
          append_event!("minecraft.world_restore.recovery_resolution_cancelled", @resolution)
          audit!("minecraft.world_restore.recovery_resolution_cancelled", @resolution)
        end
      end
      return idempotent if idempotent
      return failure(committed_failure) if committed_failure

      ServiceResult.success(
        resolution: @resolution,
        replacement: replacement,
        confirmation: replacement ? Minecraft::PlanWorldRestoreRecovery.confirmation_for(replacement) : nil,
        idempotent: false
      )
    rescue ActiveRecord::RecordNotUnique
      existing = Minecraft::WorldRestoreResolution.find_by(lifecycle_request_id: @request_id)
      return idempotent_result(existing, digest) if existing

      failure(:world_restore_recovery_idempotency_conflict)
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    rescue Minecraft::ExpireWorldRestoreRecoveryResolution::ExpirationError => error
      failure(error.message.to_sym)
    rescue LifecycleError => error
      failure(error.message.to_sym)
    end

    private

    class LifecycleError < StandardError; end

    def verify_step_up
      reservation = Administration::SensitiveActionRateLimit.call(
        scope: RATE_LIMIT_SCOPE,
        user: @actor,
        ip_address: @ip_address,
        context: [ @resolution.public_id, @lifecycle_action, @request_id ].join(":"),
        action: :reserve
      )
      if reservation.failure?
        audit_authorization_failure(rate_limited: true)
        return ServiceResult.failure(
          error: :world_restore_recovery_lifecycle_rate_limited,
          code: :rate_limited,
          retry_after: reservation.retry_after
        )
      end

      reservation_id = reservation.value.fetch(:reservation_id)
      verification = Identity::SensitiveActionVerifier.call(
        user: @actor,
        password: @password,
        code: @code
      )
      settlement_action = verification.failure? ? :failure : :success
      settlement = Administration::SensitiveActionRateLimit.call(
        scope: RATE_LIMIT_SCOPE,
        user: @actor,
        action: settlement_action,
        reservation_id: reservation_id
      )
      if verification.failure? || settlement.failure?
        audit_authorization_failure(rate_limited: false)
        return failure(:world_restore_recovery_lifecycle_authorization_failed)
      end

      ServiceResult.success(
        authorization_method: verification.value.fetch(:method),
        authorized_at: Time.current
      )
    end

    def create_replacement!(node)
      @plan.recovery_resolutions.create!(
        actor: @actor,
        status: "planned",
        resolution_action: @resolution_action,
        reason: @reason,
        request_id: @request_id,
        request_digest: lifecycle_digest,
        expected_plan_lock_version: @expected_plan_lock_version,
        plan_digest: @plan.plan_digest,
        server_configuration_digest: @plan.server_configuration_digest,
        node_capability_digest: node.world_recovery_capability_digest,
        pre_restore_manifest_digest: @plan.pre_restore_world_backup&.manifest_digest,
        expires_at: Time.current + Minecraft::PlanWorldRestoreRecovery::EXPIRES_IN,
        superseded_resolution: @resolution
      )
    end

    def bind_locked_associations(server, node, selected_backup, pre_restore_backup)
      server.association(:node).target = node
      @plan.association(:server).target = server
      @plan.association(:node).target = node
      @plan.association(:world_backup).target = selected_backup
      @plan.association(:pre_restore_world_backup).target = pre_restore_backup
    end

    def lifecycle_digest
      @lifecycle_digest ||= Minecraft::NodeOperationDigest.call(
        "actor_id" => @actor&.id,
        "plan_id" => @plan.public_id,
        "resolution_id" => @resolution.public_id,
        "lifecycle_action" => @lifecycle_action,
        "resolution_action" => @resolution_action.presence,
        "reason" => @reason,
        "request_id" => @request_id,
        "expected_plan_lock_version" => @expected_plan_lock_version,
        "expected_resolution_lock_version" => @expected_resolution_lock_version
      )
    end

    def idempotent_result(existing, digest)
      return failure(:world_restore_recovery_idempotency_conflict) unless
        existing&.id == @resolution.id &&
          existing.lifecycle_actor_id == @actor&.id &&
          existing.lifecycle_request_digest == digest &&
          existing.lifecycle_action == @lifecycle_action

      replacement = existing.superseding_resolution
      ServiceResult.success(
        resolution: existing,
        replacement: replacement,
        confirmation: replacement ? Minecraft::PlanWorldRestoreRecovery.confirmation_for(replacement) : nil,
        idempotent: true
      )
    end

    def append_event!(event_type, resolution, payload = {})
      event = Minecraft::AppendWorldRestoreEvent.call(
        plan: @plan,
        event_type: event_type,
        phase: "recovery_required",
        actor: @actor,
        payload: audit_metadata(resolution).merge(payload)
      )
      raise LifecycleError, "world_restore_event_ledger_failed" if event.failure?
    end

    def audit!(action, resolution, payload = {})
      AuditLog.record!(
        action: action,
        actor: @actor,
        resource: @plan,
        reason: @reason,
        request_id: @request_id,
        metadata: audit_metadata(resolution).merge(payload)
      )
    end

    def audit_authorization_failure(rate_limited:)
      AuditLog.record!(
        action: "minecraft.world_restore.recovery_resolution_lifecycle_authorization_failed",
        actor: @actor,
        resource: @plan,
        reason: @reason,
        request_id: @request_id,
        metadata: audit_metadata(@resolution).merge(
          lifecycle_action: @lifecycle_action,
          rate_limited: rate_limited,
          ip_digest: Digest::SHA256.hexdigest(@ip_address.to_s)[0, 12]
        )
      )
    end

    def audit_metadata(resolution)
      {
        plan_id: @plan.public_id,
        server_id: @plan.server.public_id,
        resolution_id: resolution.public_id,
        resolution_action: resolution.resolution_action,
        resolution_status: resolution.status,
        lifecycle_action: @lifecycle_action,
        prior_actor_id: @resolution.actor.public_id,
        lifecycle_actor_id: @actor&.public_id
      }
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
