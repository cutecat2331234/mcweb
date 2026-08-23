# frozen_string_literal: true

module Minecraft
  class EnqueueNodeOperation < ApplicationService
    OPERATION_TYPES = %w[
      collect_metrics
      sync_files
      world_backup_create
      world_restore_execute
      world_restore_reconcile
    ].freeze
    WORLD_OPERATION_TYPES = %w[world_backup_create world_restore_execute world_restore_reconcile].freeze
    SHA256_PATTERN = /\A[0-9a-f]{64}\z/i
    MANAGED_ID_PATTERN = /\A[A-Za-z0-9_-]{8,128}\z/
    FORBIDDEN_WORLD_PAYLOAD_KEYS = %w[
      archive archive_path destination source source_path target target_path
      compressed_limit uncompressed_limit entry_limit max_bytes max_entries
    ].freeze
    MAX_TARGETS = 5_000

    def initialize(
      operation_type:,
      servers:,
      payload: {},
      target_payloads: {},
      idempotency_key: nil
    )
      @operation_type = operation_type.to_s
      @servers = Array(servers).compact.uniq(&:id)
      @payload = payload.to_h.deep_stringify_keys
      @target_payloads = target_payloads.to_h.deep_stringify_keys
      @idempotency_key = idempotency_key.to_s.presence
    end

    def call
      validation = validate_request
      return validation if validation.failure?

      request_payload = build_request_payload
      request_digest = Minecraft::NodeOperationDigest.call(request_payload)

      if @idempotency_key && (existing = Minecraft::NodeOperation.find_by(idempotency_key: @idempotency_key))
        return idempotent_result(existing, request_digest)
      end

      operation = nil
      Minecraft::NodeOperation.transaction(requires_new: true) do
        operation = Minecraft::NodeOperation.create!(
          operation_type: @operation_type,
          status: "queued",
          idempotency_key: @idempotency_key,
          request_digest: request_digest,
          request_payload: request_payload,
          target_count: @servers.length
        )
        Minecraft::NodeOperationPreparation.record!(operation:)
      end

      ServiceResult.success(operation: operation, idempotent: false)
    rescue Operations::DurableEnqueueAdmission::Unavailable
      operation_failure(:background_processing_unavailable)
    rescue ActiveRecord::RecordNotUnique
      existing = @idempotency_key && Minecraft::NodeOperation.find_by(idempotency_key: @idempotency_key)
      return idempotent_result(existing, request_digest) if existing

      raise
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end

    private

    def validate_request
      return ServiceResult.failure(error: :unknown_node_operation_type) unless OPERATION_TYPES.include?(@operation_type)
      return ServiceResult.failure(error: :node_operation_targets_are_required) if @servers.empty?
      return ServiceResult.failure(error: :node_operation_has_too_many_targets) if @servers.length > MAX_TARGETS
      return ServiceResult.failure(error: :node_operation_target_must_be_persisted) if @servers.any?(&:new_record?)
      return ServiceResult.failure(error: :node_operation_target_has_no_node) if @servers.any? { |server| server.node.nil? }
      return ServiceResult.failure(error: :node_operation_is_not_supported_by_target_node) if @servers.any? do |server|
        !server.node.supports_node_operation?(@operation_type)
      end

      return validate_sync_request if @operation_type == "sync_files"
      return validate_world_request if WORLD_OPERATION_TYPES.include?(@operation_type)

      ServiceResult.success(true)
    end

    def validate_world_request
      return operation_failure(:world_operation_requires_one_target) unless @servers.one?
      return operation_failure(:world_operation_target_payloads_not_allowed) if @target_payloads.present?

      server = @servers.first
      payload = effective_payload(server)
      return operation_failure(:world_operation_protocol_invalid) unless payload["protocol_version"].to_i == 2
      return operation_failure(:world_operation_server_must_be_stopped) unless server.process_state_stopped?
      return operation_failure(:world_operation_working_directory_required) if server.working_directory.blank?
      return operation_failure(:world_operation_node_mismatch) unless payload["node_id"] == server.node.public_id
      return operation_failure(:world_operation_safety_profile_invalid) unless
        payload["safety_profile"] == Minecraft::WorldBackupManifest::SAFETY_PROFILE
      return operation_failure(:world_operation_contains_raw_path) if
        (payload.keys & FORBIDDEN_WORLD_PAYLOAD_KEYS).any?

      path_result = Minecraft::WorldPathPolicy.call(payload["world_relative_path"])
      return path_result if path_result.failure?

      if @operation_type == "world_backup_create"
        return operation_failure(:world_backup_id_invalid) unless managed_id?(payload["backup_id"])
        return operation_failure(:world_backup_request_digest_invalid) unless sha256?(payload["request_digest"])
        return operation_failure(:world_backup_purpose_invalid) unless
          Minecraft::WorldBackup::PURPOSES.include?(payload["purpose"].to_s)
        return operation_failure(:world_backup_node_capability_required) unless
          server.node.supports_managed_world_backups_v2?
      elsif @operation_type == "world_restore_execute"
        %w[plan_id backup_id pre_restore_backup_id].each do |key|
          return operation_failure(:world_restore_managed_id_invalid) unless managed_id?(payload[key])
        end
        %w[plan_digest backup_manifest_digest server_configuration_digest].each do |key|
          return operation_failure(:world_restore_digest_invalid) unless sha256?(payload[key])
        end
        return operation_failure(:world_restore_expected_state_invalid) unless
          payload["expected_process_state"] == "stopped"
        return operation_failure(:world_restore_node_capability_required) unless
          server.node.supports_managed_world_backups_v2? && server.node.supports_world_restore_v2?
      else
        %w[resolution_id plan_id backup_id].each do |key|
          return operation_failure(:world_restore_managed_id_invalid) unless managed_id?(payload[key])
        end
        return operation_failure(:world_restore_recovery_action_invalid) unless
          Minecraft::WorldRestoreResolution::ACTIONS.include?(payload["resolution_action"].to_s)
        %w[
          reason_digest plan_digest backup_manifest_digest server_configuration_digest
          recovery_capability_digest
        ].each do |key|
          return operation_failure(:world_restore_digest_invalid) unless sha256?(payload[key])
        end
        if payload["pre_restore_backup_id"].present?
          return operation_failure(:world_restore_managed_id_invalid) unless
            managed_id?(payload["pre_restore_backup_id"])
        end
        if payload["pre_restore_manifest_digest"].present?
          return operation_failure(:world_restore_digest_invalid) unless
            sha256?(payload["pre_restore_manifest_digest"])
        end
        if payload["resolution_action"].to_s.in?(%w[resume rollback])
          return operation_failure(:world_restore_recovery_pre_snapshot_required) unless
            managed_id?(payload["pre_restore_backup_id"]) && sha256?(payload["pre_restore_manifest_digest"])
        end
        return operation_failure(:world_restore_expected_state_invalid) unless
          payload["expected_process_state"] == "stopped"
        return operation_failure(:world_restore_recovery_capability_required) unless
          server.node.supports_world_restore_recovery_v2?
      end

      ServiceResult.success(true)
    end

    def validate_sync_request
      @servers.map { |server| effective_payload(server) }.uniq.each do |payload|
        url_check = Minecraft::ValidateSyncFileUrl.call(url: payload["url"])
        return url_check if url_check.failure?
        return ServiceResult.failure(error: :sync_file_sha256_is_required) unless payload["sha256"].to_s.match?(SHA256_PATTERN)
        return ServiceResult.failure(error: :sync_file_revision_is_required) if payload["revision"].blank?
        return ServiceResult.failure(error: :sync_file_relative_path_is_invalid) unless safe_relative_path?(payload["relative_path"])
        return ServiceResult.failure(error: :sync_file_absolute_destination_is_not_allowed) if payload["destination"].present?
      end
      return ServiceResult.failure(error: :sync_file_target_has_no_working_directory) if @servers.any? { |server| server.working_directory.blank? }

      ServiceResult.success(true)
    end

    def safe_relative_path?(value)
      path = value.to_s.tr("\\", "/")
      return false if path.blank? || path.start_with?("/") || path.match?(/\A[A-Za-z]:/)

      path.split("/").none? { |part| part == ".." }
    end

    def managed_id?(value)
      value.to_s.match?(MANAGED_ID_PATTERN)
    end

    def sha256?(value)
      value.to_s.match?(SHA256_PATTERN)
    end

    def operation_failure(code)
      ServiceResult.failure(error: code, code: code)
    end

    def build_request_payload
      {
        "protocol_version" => 2,
        "operation_type" => @operation_type,
        "shared_payload" => @payload,
        "targets" => @servers.sort_by(&:public_id).map { |server| build_target(server) }
      }
    end

    def build_target(server)
      target_payload = @target_payloads.fetch(server.public_id, {}).merge(
        "server_id" => server.public_id,
        "working_directory" => server.working_directory,
        "process_driver" => server.process_driver,
        "process_config" => server.process_config
      )

      {
        "target_key" => server.public_id,
        "server_id" => server.public_id,
        "node_id" => server.node.public_id,
        "task_type" => @operation_type,
        "expected_revision" => effective_payload(server)["revision"],
        "payload" => target_payload
      }
    end

    def effective_payload(server)
      @payload.deep_merge(@target_payloads.fetch(server.public_id, {}))
    end

    def idempotent_result(existing, request_digest)
      return ServiceResult.failure(error: :node_operation_idempotency_conflict) unless existing&.request_digest == request_digest

      ServiceResult.success(operation: existing, idempotent: true)
    end
  end
end
