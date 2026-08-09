# frozen_string_literal: true

module Minecraft
  class NodeOperationDispatcher < ApplicationService
    LEASE_DURATION = 5.minutes

    def initialize(node:, batch_id: nil, envelope: {}, action: :claim)
      @node = node
      @batch_id = batch_id.to_s
      @envelope = envelope.to_h.deep_stringify_keys
      @action = action
    end

    def call
      case @action
      when :claim then claim_batch
      when :lease then renew_lease
      when :complete then record_result
      when :acknowledge then acknowledge_result
      else ServiceResult.failure(error: :unknown_node_operation_action)
      end
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end

    private

    def claim_batch
      claimed = nil
      blocked_by = nil

      Minecraft::NodeOperationBatch.transaction do
        @node.lock!
        legacy_task = @node.node_tasks.where(status: "claimed").lock.first
        if legacy_task
          blocked_by = "legacy-task:#{legacy_task.id}"
          next
        end
        if @node.node_tasks.where(status: "pending", priority: "urgent").exists?
          blocked_by = "legacy-urgent-task"
          next
        end
        active = @node.operation_batches.active.lock.first
        if active
          blocked_by = active.public_id
          next
        end

        claimed = @node.operation_batches.dispatchable.lock.first
        next unless claimed

        now = Time.current
        claimed.update!(
          status: "dispatched",
          claimed_at: now,
          lease_expires_at: now + LEASE_DURATION,
          delivery_attempts: claimed.delivery_attempts + 1
        )
        claimed.operation.update!(
          status: "running",
          started_at: claimed.operation.started_at || now
        ) unless claimed.operation.status_running?
      end

      ServiceResult.success(batch: claimed, blocked_by: blocked_by)
    end

    def renew_lease
      batch = find_batch
      return ServiceResult.failure(error: :node_operation_batch_not_found) unless batch

      batch.with_lock do
        return delivery_mismatch unless matching_delivery?(batch)
        return terminal_result(batch) if batch.terminal?
        return ServiceResult.failure(error: :node_operation_result_is_waiting_for_ack) if batch.status_result_pending_ack?
        return ServiceResult.failure(error: :node_operation_batch_is_not_active) unless batch.active?

        now = Time.current
        batch.update!(
          status: "running",
          started_at: batch.started_at || now,
          lease_expires_at: now + LEASE_DURATION
        )
      end

      ServiceResult.success(batch: batch, acknowledged: false)
    end

    def record_result
      batch = find_batch
      return ServiceResult.failure(error: :node_operation_batch_not_found) unless batch

      response = nil
      batch.with_lock do
        return response = delivery_mismatch unless matching_delivery?(batch)
        result_digest = Minecraft::NodeOperationDigest.call(@envelope.fetch("target_results", []))
        if batch.terminal?
          return response = ServiceResult.failure(error: :node_operation_result_conflict) if batch.result_digest != result_digest

          return response = terminal_result(batch)
        end
        if batch.status_result_pending_ack?
          return response = ServiceResult.failure(error: :node_operation_result_conflict) if batch.result_digest != result_digest

          return response = pending_ack_result(batch, idempotent: true)
        end
        return response = ServiceResult.failure(error: :node_operation_batch_is_not_active) unless batch.active?

        normalized_results = validate_and_normalize_results(batch)
        return response = normalized_results if normalized_results.failure?

        persist_results!(batch, normalized_results.value.fetch(:results), result_digest)
        response = pending_ack_result(batch, idempotent: false)
      end
      response
    end

    def acknowledge_result
      batch = find_batch
      return ServiceResult.failure(error: :node_operation_batch_not_found) unless batch

      should_reconcile = false
      response = nil
      batch.with_lock do
        return response = delivery_mismatch unless matching_delivery?(batch)
        unless ActiveSupport::SecurityUtils.secure_compare(
          batch.acknowledgement_id.to_s,
          @envelope["acknowledgement_id"].to_s
        )
          return response = ServiceResult.failure(error: :node_operation_acknowledgement_mismatch)
        end
        return response = terminal_result(batch) if batch.terminal?
        return response = ServiceResult.failure(error: :node_operation_result_is_not_ready) unless batch.status_result_pending_ack?

        terminal_status = batch.failed_target_count.zero? ? "completed" : "completed_with_errors"
        now = Time.current
        batch.update!(
          status: terminal_status,
          acknowledged_at: now,
          completed_at: now,
          lease_expires_at: nil
        )
        should_reconcile = true
        response = ServiceResult.success(batch: batch, acknowledged: true, idempotent: false)
      end

      Minecraft::ReconcileNodeOperationJob.perform_later(batch.operation_id) if should_reconcile
      response
    end

    def find_batch
      @node.operation_batches.find_by(public_id: @batch_id)
    end

    def matching_delivery?(batch)
      delivery_matches = ActiveSupport::SecurityUtils.secure_compare(
        batch.delivery_id,
        @envelope["delivery_id"].to_s
      )
      digest_matches = ActiveSupport::SecurityUtils.secure_compare(
        batch.payload_digest,
        @envelope["payload_digest"].to_s
      )
      delivery_matches && digest_matches
    end

    def delivery_mismatch
      ServiceResult.failure(error: :node_operation_delivery_mismatch)
    end

    def validate_and_normalize_results(batch)
      raw_results = @envelope["target_results"]
      return ServiceResult.failure(error: :node_operation_target_results_are_required) unless raw_results.is_a?(Array)

      expected_targets = batch.payload.fetch("targets").index_by { |target| target.fetch("target_key") }
      reported_keys = raw_results.map { |result| result.to_h["target_key"].to_s }
      return ServiceResult.failure(error: :node_operation_target_results_are_incomplete) unless reported_keys.sort == expected_targets.keys.sort
      return ServiceResult.failure(error: :node_operation_target_results_are_duplicated) unless reported_keys.uniq.length == reported_keys.length

      normalized = raw_results.map do |raw_result|
        result = raw_result.to_h.deep_stringify_keys
        return ServiceResult.failure(error: :node_operation_target_status_is_invalid) unless %w[completed failed].include?(result["status"])

        target = expected_targets.fetch(result["target_key"])
        normalized_status = result["status"]
        applied_revision = result["applied_revision"].to_s.presence
        error_code = result["error_code"].to_s.presence
        error_message = result["error_message"].to_s.presence
        if batch.operation.operation_type == "sync_files" &&
            normalized_status == "completed" &&
            applied_revision != target["expected_revision"].to_s
          normalized_status = "failed"
          error_code = "revision_mismatch"
          error_message = "node reported a revision other than the frozen target revision"
        end
        {
          target: target,
          status: normalized_status,
          applied_revision: applied_revision,
          result: result["result"].is_a?(Hash) ? result["result"] : {},
          error_code: error_code,
          error_message: error_message,
          started_at: parse_time(result["started_at"]),
          completed_at: parse_time(result["completed_at"]) || Time.current
        }
      end

      ServiceResult.success(results: normalized)
    end

    def persist_results!(batch, results, result_digest)
      results.each do |entry|
        target = entry.fetch(:target)
        batch.target_results.create!(
          server: Minecraft::Server.find_by(public_id: target["server_id"]),
          target_key: target.fetch("target_key"),
          status: entry.fetch(:status),
          expected_revision: target["expected_revision"],
          applied_revision: entry[:applied_revision],
          result: entry.fetch(:result),
          error_code: entry[:error_code],
          error_message: entry[:error_message],
          started_at: entry[:started_at],
          completed_at: entry[:completed_at]
        )
      end

      completed_count = results.count { |entry| entry[:status] == "completed" }
      failed_count = results.length - completed_count
      now = Time.current
      batch.update!(
        status: "result_pending_ack",
        result_digest: result_digest,
        acknowledgement_id: SecureRandom.uuid,
        completed_target_count: completed_count,
        failed_target_count: failed_count,
        result: {
          "completed_target_count" => completed_count,
          "failed_target_count" => failed_count
        },
        result_recorded_at: now,
        lease_expires_at: nil
      )
    end

    def pending_ack_result(batch, idempotent:)
      ServiceResult.success(
        batch: batch,
        acknowledgement_id: batch.acknowledgement_id,
        acknowledged: false,
        idempotent: idempotent
      )
    end

    def terminal_result(batch)
      ServiceResult.success(batch: batch, acknowledged: true, idempotent: true)
    end

    def parse_time(value)
      return if value.blank?

      Time.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
