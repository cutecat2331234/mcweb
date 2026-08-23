# frozen_string_literal: true

module Minecraft
  class ReconcileWorldOperation < ApplicationService
    WORLD_OPERATION_TYPES = %w[
      world_backup_create world_restore_execute world_restore_reconcile
    ].freeze
    RESTORE_PHASES = %w[
      accepted process_stopped pre_snapshot_started pre_snapshot_durable archive_validated
      staging_started staging_verified live_preserved replacement_installed post_install_verified
      rollback_started rolled_back completed recovery_required
    ].freeze
    SAFE_FAILURE_PHASES = %w[
      accepted process_stopped pre_snapshot_started pre_snapshot_durable archive_validated
      staging_started staging_verified
    ].freeze
    ERROR_CODE_PATTERN = /\A[a-z][a-z0-9_]{0,99}\z/
    SHA256_PATTERN = /\A[0-9a-f]{64}\z/

    def initialize(operation:, action:, target_result: nil)
      @operation = operation
      @action = action.to_sym
      @target_result = target_result
    end

    def call
      return ServiceResult.success(ignored: true) unless WORLD_OPERATION_TYPES.include?(@operation.operation_type)

      case @action
      when :started then mark_started
      when :target_result then apply_target_result
      when :terminal then apply_unreported_terminal_failure
      else failure(:world_operation_reconciliation_action_invalid)
      end
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    rescue ReconciliationError => error
      failure(error.message.to_sym)
    end

    private

    class ReconciliationError < StandardError; end

    def mark_started
      if @operation.operation_type == "world_backup_create"
        backup = @operation.world_backup
        return ServiceResult.success(ignored: true) unless backup

        backup.with_lock do
          backup.update!(status: "creating") if backup.status_queued?
        end
      elsif @operation.operation_type == "world_restore_execute"
        plan = @operation.world_restore_plan
        return ServiceResult.success(ignored: true) unless plan

        changed = false
        plan.with_lock do
          if plan.status_queued?
            plan.update!(status: "running", started_at: plan.started_at || Time.current)
            append_event!(plan, "minecraft.world_restore.started", "running", operation_id: @operation.public_id)
            changed = true
          end
        end
        audit_restore("minecraft.world_restore.started", plan) if changed
      else
        resolution = @operation.world_restore_resolution
        return ServiceResult.success(ignored: true) unless resolution

        plan = resolution.restore_plan
        changed = false
        plan.with_lock do
          resolution.lock!
          if resolution.status_queued?
            resolution.update!(status: "running", started_at: resolution.started_at || Time.current)
            append_event!(
              plan,
              "minecraft.world_restore.recovery_resolution_started",
              "recovery_required",
              resolution_id: resolution.public_id,
              resolution_action: resolution.resolution_action,
              operation_id: @operation.public_id
            )
            changed = true
          end
        end
        audit_resolution("minecraft.world_restore.recovery_resolution_started", resolution) if changed
      end

      ServiceResult.success(operation: @operation)
    end

    def apply_target_result
      raise ReconciliationError, "world_operation_target_result_required" unless @target_result

      case @operation.operation_type
      when "world_backup_create" then apply_backup_result
      when "world_restore_execute" then apply_restore_result
      else apply_recovery_resolution_result
      end
    end

    def apply_backup_result
      backup = @operation.world_backup
      return failure(:world_backup_record_not_found) unless backup

      if @target_result.status_completed?
        raw_manifest = @target_result.result.to_h.deep_stringify_keys["backup"]
        manifest_result = Minecraft::WorldBackupManifest.normalize(raw_manifest, backup: backup)
        return fail_backup(backup, manifest_result.code || :world_backup_manifest_invalid) if manifest_result.failure?

        summary = manifest_result.value.fetch(:summary)
        changed = false
        backup.with_lock do
          unless backup.status_available?
            backup.update!(
              status: "available",
              manifest_version: summary.fetch("manifest_version"),
              safety_profile: summary.fetch("safety_profile"),
              archive_format: summary.fetch("archive_format"),
              manifest_digest: summary.fetch("manifest_digest"),
              archive_sha256: summary.fetch("archive_sha256"),
              archive_bytes: summary.fetch("archive_bytes"),
              uncompressed_bytes: summary.fetch("uncompressed_bytes"),
              entry_count: summary.fetch("entry_count"),
              manifest_summary: summary,
              verified_at: Time.current,
              failed_at: nil,
              error_code: nil
            )
            changed = true
          end
        end
        if changed
          AuditLog.record!(
            action: "minecraft.world_backup.available",
            resource: backup,
            request_id: backup.request_id,
            metadata: backup_audit_metadata(backup)
          )
        end
        ServiceResult.success(backup: backup)
      else
        fail_backup(backup, stable_error_code(@target_result.error_code, "world_backup_node_failed"))
      end
    end

    def apply_restore_result
      plan = @operation.world_restore_plan
      return failure(:world_restore_plan_not_found) unless plan

      raw = @target_result.result.to_h.deep_stringify_keys["restore"]
      summary = normalize_restore_summary(raw, plan)
      return mark_restore_recovery_required(plan, "world_restore_result_invalid") unless summary

      quarantine_selected_backup(plan, summary["error_code"])
      pre_backup_result = apply_pre_restore_backup(plan, summary["pre_restore_backup"])
      fail_unavailable_pre_backup(plan, "world_restore_pre_snapshot_missing") if pre_backup_result.failure?
      if pre_backup_result.failure? && !safe_failure?(summary)
        return mark_restore_recovery_required(plan, "world_restore_pre_snapshot_invalid")
      end

      status, error_code = restore_outcome(summary)
      if status == "recovery_required"
        return mark_restore_recovery_required(plan, error_code)
      end

      changed = false
      plan.with_lock do
        next if plan.terminal?

        now = Time.current
        attributes = {
          status: status,
          result_summary: public_restore_summary(summary),
          error_code: error_code,
          completed_at: now,
          failed_at: status == "completed" ? nil : now,
          started_at: plan.started_at || parse_time(summary["started_at"]) || now
        }
        plan.update!(attributes)
        append_event!(plan, restore_event_type(status), status, attributes[:result_summary])
        changed = true
      end
      audit_restore(restore_event_type(status), plan) if changed
      ServiceResult.success(plan: plan)
    end

    def apply_recovery_resolution_result
      resolution = @operation.world_restore_resolution
      return failure(:world_restore_recovery_resolution_not_found) unless resolution

      plan = resolution.restore_plan
      raw = @target_result.result.to_h.deep_stringify_keys["recovery_resolution"]
      summary = normalize_recovery_resolution_summary(raw, resolution)
      return mark_resolution_recovery_required(resolution, "world_restore_recovery_result_invalid") unless summary

      pre_backup_result = apply_pre_restore_backup(plan, summary["pre_restore_backup"])
      if pre_backup_result.failure? && summary["phase"] == "rolled_back"
        return mark_resolution_recovery_required(resolution, "world_restore_pre_snapshot_invalid")
      end
      if summary["recovery_required"] || !summary["recovery_resolution_proof"]
        return mark_resolution_recovery_required(
          resolution,
          summary["error_code"] || "world_restore_recovery_unresolved",
          summary: summary
        )
      end

      changed = false
      Minecraft::WorldRestorePlan.transaction do
        plan.lock!
        resolution.lock!
        next if resolution.status_completed? && plan.terminal?
        unless plan.status_recovery_required? && resolution.status.in?(%w[queued running])
          raise ReconciliationError, "world_restore_recovery_state_changed"
        end

        status = summary.fetch("phase")
        now = Time.current
        public_summary = public_recovery_resolution_summary(summary)
        resolution.update!(
          status: "completed",
          result_summary: public_summary,
          error_code: summary["error_code"],
          started_at: resolution.started_at || parse_time(summary["started_at"]) || now,
          completed_at: now
        )
        plan.update!(
          status: status,
          result_summary: public_summary.merge(
            "pre_restore_backup_id" => plan.pre_restore_world_backup&.public_id
          ).compact,
          error_code: summary["error_code"],
          completed_at: now,
          failed_at: status == "completed" ? nil : now
        )
        append_event!(
          plan,
          "minecraft.world_restore.recovery_resolution_completed",
          status,
          public_summary
        )
        changed = true
      end
      audit_resolution("minecraft.world_restore.recovery_resolution_completed", resolution) if changed
      ServiceResult.success(plan: plan, resolution: resolution)
    end

    def normalize_recovery_resolution_summary(value, resolution)
      return unless value.is_a?(Hash)

      summary = value.deep_stringify_keys
      plan = resolution.restore_plan
      return unless summary["resolution_id"] == resolution.public_id
      return unless summary["resolution_action"] == resolution.resolution_action
      return unless summary["plan_id"] == plan.public_id && summary["plan_digest"] == plan.plan_digest
      return unless summary["server_configuration_digest"] == plan.server_configuration_digest
      return unless summary["world_relative_path"] == plan.world_relative_path
      return unless %w[completed rolled_back recovery_required].include?(summary["phase"].to_s)
      return unless [ true, false ].include?(summary["rolled_back"])
      return unless [ true, false ].include?(summary["recovery_required"])
      return unless [ true, false ].include?(summary["recovery_resolution_proof"])

      started_at = parse_time(summary["started_at"])
      completed_at = parse_time(summary["completed_at"])
      return unless started_at && completed_at && completed_at >= started_at
      return if completed_at > 5.minutes.from_now

      installed_digest = summary["installed_manifest_digest"].to_s
      if summary["phase"] == "completed"
        return unless @target_result.status_completed?
        return unless summary["recovery_resolution_proof"] && !summary["recovery_required"] &&
          !summary["rolled_back"] && summary["verified_world_state"] == "selected"
        return unless installed_digest == plan.backup_manifest_digest
        return if summary["error_code"].present? || @target_result.error_code.present?
      elsif summary["phase"] == "rolled_back"
        return unless summary["recovery_resolution_proof"] && !summary["recovery_required"] &&
          summary["rolled_back"] && summary["verified_world_state"].in?(%w[pre_restore original_absent])
        return if summary["error_code"].blank?
      else
        return if summary["recovery_resolution_proof"] || !summary["recovery_required"]
      end

      {
        "resolution_id" => resolution.public_id,
        "resolution_action" => resolution.resolution_action,
        "plan_id" => plan.public_id,
        "plan_digest" => plan.plan_digest,
        "phase" => summary["phase"],
        "installed_manifest_digest" => installed_digest.presence,
        "rolled_back" => summary["rolled_back"],
        "recovery_required" => summary["recovery_required"],
        "recovery_resolution_proof" => summary["recovery_resolution_proof"],
        "verified_world_state" => summary["verified_world_state"].to_s.presence,
        "server_configuration_digest" => plan.server_configuration_digest,
        "world_relative_path" => plan.world_relative_path,
        "error_code" => stable_error_code(summary["error_code"] || @target_result.error_code, nil),
        "started_at" => started_at.utc.iso8601(6),
        "completed_at" => completed_at.utc.iso8601(6),
        "pre_restore_backup" => summary["pre_restore_backup"]
      }.compact
    end

    def mark_resolution_recovery_required(resolution, code, summary: nil)
      changed = false
      plan = resolution.restore_plan
      plan.with_lock do
        resolution.lock!
        unless resolution.terminal?
          normalized = stable_error_code(code, "world_restore_recovery_unresolved")
          public_summary = summary ? public_recovery_resolution_summary(summary) : {
            "resolution_id" => resolution.public_id,
            "resolution_action" => resolution.resolution_action,
            "plan_id" => plan.public_id,
            "phase" => "recovery_required",
            "rolled_back" => false,
            "recovery_required" => true,
            "recovery_resolution_proof" => false,
            "error_code" => normalized
          }
          resolution.update!(
            status: "recovery_required",
            result_summary: public_summary,
            error_code: normalized,
            started_at: resolution.started_at || Time.current,
            completed_at: Time.current
          )
          append_event!(
            plan,
            "minecraft.world_restore.recovery_resolution_failed",
            "recovery_required",
            public_summary
          )
          changed = true
        end
      end
      audit_resolution("minecraft.world_restore.recovery_resolution_failed", resolution) if changed
      ServiceResult.success(plan: plan, resolution: resolution, recovery_required: true)
    end

    def apply_pre_restore_backup(plan, raw_manifest)
      backup = plan.pre_restore_world_backup
      return failure(:world_restore_pre_snapshot_missing) unless backup
      return ServiceResult.success(backup: backup) if backup.status_available?
      return failure(:world_restore_pre_snapshot_missing) unless raw_manifest.is_a?(Hash)

      manifest_result = Minecraft::WorldBackupManifest.normalize(raw_manifest, backup: backup)
      return manifest_result if manifest_result.failure?

      summary = manifest_result.value.fetch(:summary)
      backup.with_lock do
        backup.update!(
          status: "available",
          manifest_version: summary.fetch("manifest_version"),
          safety_profile: summary.fetch("safety_profile"),
          archive_format: summary.fetch("archive_format"),
          manifest_digest: summary.fetch("manifest_digest"),
          archive_sha256: summary.fetch("archive_sha256"),
          archive_bytes: summary.fetch("archive_bytes"),
          uncompressed_bytes: summary.fetch("uncompressed_bytes"),
          entry_count: summary.fetch("entry_count"),
          manifest_summary: summary,
          verified_at: Time.current,
          failed_at: nil,
          error_code: nil
        )
      end
      append_event!(
        plan,
        "minecraft.world_restore.pre_snapshot_available",
        "pre_snapshot_durable",
        pre_restore_backup_id: backup.public_id,
        manifest_digest: backup.manifest_digest.last(12)
      )
      AuditLog.record!(
        action: "minecraft.world_restore.pre_snapshot_available",
        resource: plan,
        request_id: plan.request_id,
        metadata: restore_audit_metadata(plan).merge(pre_restore_backup_id: backup.public_id)
      )
      ServiceResult.success(backup: backup)
    end

    def normalize_restore_summary(value, plan)
      return unless value.is_a?(Hash)

      summary = value.deep_stringify_keys
      return unless summary["plan_id"] == plan.public_id
      return unless RESTORE_PHASES.include?(summary["phase"].to_s)
      return unless [ true, false ].include?(summary["rolled_back"])
      return unless [ true, false ].include?(summary["recovery_required"])

      started_at = parse_time(summary["started_at"])
      completed_at = parse_time(summary["completed_at"])
      return unless started_at && completed_at && completed_at >= started_at
      return if completed_at > 5.minutes.from_now

      installed_digest = summary["installed_manifest_digest"].to_s
      return unless installed_digest.blank? || installed_digest.match?(SHA256_PATTERN)
      if summary["phase"] == "completed"
        return unless @target_result.status_completed?
        return unless installed_digest == plan.backup_manifest_digest
        return if summary["rolled_back"] || summary["recovery_required"]
        return if summary["error_code"].present? || @target_result.error_code.present?
      end
      return if summary["rolled_back"] && summary["recovery_required"]

      {
        "plan_id" => plan.public_id,
        "phase" => summary["phase"],
        "installed_manifest_digest" => installed_digest.presence,
        "rolled_back" => summary["rolled_back"],
        "recovery_required" => summary["recovery_required"],
        "error_code" => stable_error_code(summary["error_code"] || @target_result.error_code, nil),
        "started_at" => started_at.utc.iso8601(6),
        "completed_at" => completed_at.utc.iso8601(6),
        "pre_restore_backup" => summary["pre_restore_backup"]
      }.compact
    end

    def restore_outcome(summary)
      return [ "recovery_required", summary["error_code"] || "world_restore_recovery_required" ] if
        summary["recovery_required"] || summary["phase"] == "recovery_required"
      return [ "rolled_back", summary["error_code"] || "world_restore_rolled_back" ] if
        summary["rolled_back"] && summary["phase"] == "rolled_back"
      return [ "completed", nil ] if summary["phase"] == "completed"
      return [ "failed", summary["error_code"] || "world_restore_node_failed" ] if safe_failure?(summary)

      [ "recovery_required", "world_restore_ambiguous_node_result" ]
    end

    def safe_failure?(summary)
      !summary["recovery_required"] && SAFE_FAILURE_PHASES.include?(summary["phase"])
    end

    def mark_restore_recovery_required(plan, code)
      changed = false
      plan.with_lock do
        unless plan.status_recovery_required?
          now = Time.current
          plan.update!(
            status: "recovery_required",
            failed_at: now,
            error_code: stable_error_code(code, "world_restore_recovery_required"),
            result_summary: {
              "phase" => "recovery_required",
              "recovery_required" => true,
              "rolled_back" => false
            }
          )
          append_event!(
            plan,
            "minecraft.world_restore.recovery_required",
            "recovery_required",
            error_code: plan.error_code
          )
          changed = true
        end
      end
      fail_unavailable_pre_backup(plan, plan.error_code)
      audit_restore("minecraft.world_restore.recovery_required", plan) if changed
      ServiceResult.success(plan: plan, recovery_required: true)
    end

    def apply_unreported_terminal_failure
      if @operation.operation_type == "world_backup_create"
        backup = @operation.world_backup
        return ServiceResult.success(ignored: true) unless backup && !backup.status_available? && !backup.status_failed?

        fail_backup(backup, "world_backup_unreported_node_failure")
      elsif @operation.operation_type == "world_restore_execute"
        plan = @operation.world_restore_plan
        return ServiceResult.success(ignored: true) unless plan && !plan.terminal? && !plan.status_recovery_required?

        mark_restore_recovery_required(plan, "world_restore_unreported_node_failure")
      else
        resolution = @operation.world_restore_resolution
        return ServiceResult.success(ignored: true) unless resolution && !resolution.terminal?

        mark_resolution_recovery_required(resolution, "world_restore_recovery_unreported_node_failure")
      end
    end

    def fail_backup(backup, code)
      normalized = stable_error_code(code, "world_backup_failed")
      changed = false
      backup.with_lock do
        unless backup.status_available? || backup.status_failed?
          backup.update!(status: "failed", failed_at: Time.current, error_code: normalized)
          changed = true
        end
      end
      if changed
        AuditLog.record!(
          action: "minecraft.world_backup.failed",
          resource: backup,
          request_id: backup.request_id,
          metadata: backup_audit_metadata(backup).merge(error_code: normalized)
        )
      end
      ServiceResult.success(backup: backup)
    end

    def fail_unavailable_pre_backup(plan, code)
      backup = plan.pre_restore_world_backup
      return unless backup && !backup.status_available? && !backup.status_failed?

      backup.update!(status: "failed", failed_at: Time.current, error_code: code)
    end

    def quarantine_selected_backup(plan, code)
      value = code.to_s
      integrity_failure = value.in?(%w[backup_not_found backup_directory_unsafe]) ||
        value.start_with?("backup_manifest_", "manifest_", "archive_")
      return unless integrity_failure

      backup = plan.world_backup
      changed = false
      backup.with_lock do
        if backup.status_available?
          backup.update!(status: "quarantined", failed_at: Time.current, error_code: value)
          changed = true
        end
      end
      return unless changed

      AuditLog.record!(
        action: "minecraft.world_backup.quarantined",
        resource: backup,
        request_id: backup.request_id,
        metadata: backup_audit_metadata(backup).merge(error_code: value)
      )
    end

    def append_event!(plan, event_type, phase, payload = {})
      result = Minecraft::AppendWorldRestoreEvent.call(
        plan: plan,
        event_type: event_type,
        phase: phase,
        payload: restore_audit_metadata(plan).merge(payload)
      )
      raise ReconciliationError, "world_restore_event_ledger_failed" if result.failure?
    end

    def audit_restore(action, plan)
      AuditLog.record!(
        action: action,
        resource: plan,
        reason: plan.reason,
        request_id: plan.request_id,
        metadata: restore_audit_metadata(plan)
      )
    end

    def audit_resolution(action, resolution)
      plan = resolution.restore_plan
      AuditLog.record!(
        action: action,
        actor: resolution.actor,
        resource: plan,
        reason: resolution.reason,
        request_id: resolution.request_id,
        metadata: restore_audit_metadata(plan).merge(
          resolution_id: resolution.public_id,
          resolution_action: resolution.resolution_action,
          resolution_status: resolution.status,
          resolution_operation_id: resolution.node_operation&.public_id
        )
      )
    end

    def backup_audit_metadata(backup)
      {
        backup_id: backup.public_id,
        server_id: backup.server.public_id,
        purpose: backup.purpose,
        status: backup.status,
        archive_bytes: backup.archive_bytes,
        uncompressed_bytes: backup.uncompressed_bytes,
        entry_count: backup.entry_count,
        manifest_digest: backup.manifest_digest&.last(12)
      }.compact
    end

    def restore_audit_metadata(plan)
      {
        plan_id: plan.public_id,
        server_id: plan.server.public_id,
        backup_id: plan.world_backup.public_id,
        pre_restore_backup_id: plan.pre_restore_world_backup&.public_id,
        operation_id: plan.node_operation&.public_id,
        status: plan.status,
        phase: plan.result_summary.to_h["phase"],
        error_code: plan.error_code,
        manifest_digest: plan.backup_manifest_digest.last(12)
      }.compact
    end

    def public_restore_summary(summary)
      {
        "phase" => summary["phase"],
        "installed_manifest_digest" => summary["installed_manifest_digest"],
        "rolled_back" => summary["rolled_back"],
        "recovery_required" => summary["recovery_required"],
        "started_at" => summary["started_at"],
        "completed_at" => summary["completed_at"],
        "pre_restore_backup_id" => @operation.world_restore_plan.pre_restore_world_backup&.public_id
      }.compact
    end

    def public_recovery_resolution_summary(summary)
      {
        "resolution_id" => summary["resolution_id"],
        "resolution_action" => summary["resolution_action"],
        "plan_id" => summary["plan_id"],
        "plan_digest" => summary["plan_digest"],
        "phase" => summary["phase"],
        "installed_manifest_digest" => summary["installed_manifest_digest"],
        "rolled_back" => summary["rolled_back"],
        "recovery_required" => summary["recovery_required"],
        "recovery_resolution_proof" => summary["recovery_resolution_proof"],
        "verified_world_state" => summary["verified_world_state"],
        "server_configuration_digest" => summary["server_configuration_digest"],
        "world_relative_path" => summary["world_relative_path"],
        "error_code" => summary["error_code"],
        "started_at" => summary["started_at"],
        "completed_at" => summary["completed_at"]
      }.compact
    end

    def restore_event_type(status)
      "minecraft.world_restore.#{status}"
    end

    def stable_error_code(value, fallback)
      code = value.to_s
      return code if code.match?(ERROR_CODE_PATTERN)

      fallback
    end

    def parse_time(value)
      return if value.blank?

      Time.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
