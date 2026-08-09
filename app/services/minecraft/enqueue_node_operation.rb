# frozen_string_literal: true

module Minecraft
  class EnqueueNodeOperation < ApplicationService
    OPERATION_TYPES = %w[collect_metrics sync_files].freeze
    SHA256_PATTERN = /\A[0-9a-f]{64}\z/i
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

      operation = Minecraft::NodeOperation.create!(
        operation_type: @operation_type,
        status: "queued",
        idempotency_key: @idempotency_key,
        request_digest: request_digest,
        request_payload: request_payload,
        target_count: @servers.length
      )
      Minecraft::PrepareNodeOperationJob.perform_later

      ServiceResult.success(operation: operation, idempotent: false)
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
