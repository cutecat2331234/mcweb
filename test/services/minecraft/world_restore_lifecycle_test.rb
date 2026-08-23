# frozen_string_literal: true

require "test_helper"

class Minecraft::WorldRestoreLifecycleTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    @actor = create_user
    grant_permission(@actor, "minecraft.world_restores.execute")
    @node = Minecraft::Node.create!(
      name: "World Safety Node",
      status: :online,
      last_heartbeat_at: Time.current,
      metadata: world_safety_metadata
    )
    @server = Minecraft::Server.create!(
      name: "World Safety Server",
      node: @node,
      process_driver: "script",
      process_config: { "status" => "./status.sh" },
      process_state: :stopped,
      working_directory: "/srv/minecraft/world-safety",
      metadata: { "world_directory" => "world" }
    )
    @backup = create_available_backup
  end

  teardown do
    clear_enqueued_jobs
  end

  test "plan authorization execution and acknowledged node result close the safety lifecycle" do
    request_id = SecureRandom.uuid
    planned = Minecraft::PlanWorldRestore.call(
      server: @server,
      backup: @backup,
      actor: @actor,
      reason: "Restore incident INC-42",
      request_id: request_id
    )
    assert_predicate planned, :success?
    plan = planned.value.fetch(:plan)
    assert plan.status_planned?
    assert_equal 1, plan.events.count

    replay = Minecraft::PlanWorldRestore.call(
      server: @server,
      backup: @backup,
      actor: @actor,
      reason: "Restore incident INC-42",
      request_id: request_id
    )
    assert_predicate replay, :success?
    assert replay.value.fetch(:idempotent)
    assert_equal plan.id, replay.value.fetch(:plan).id

    authorization = Minecraft::AuthorizeWorldRestore.call(
      plan: plan,
      actor: @actor,
      password: "password123"
    )
    assert_predicate authorization, :success?
    token = authorization.value.fetch(:authorization_token)
    confirmation = authorization.value.fetch(:confirmation)
    assert plan.reload.status_authorized?

    mismatch = Minecraft::ExecuteWorldRestore.call(
      plan: plan,
      actor: @actor,
      authorization_token: token,
      confirmation: "RESTORE THE WRONG PLAN"
    )
    assert_predicate mismatch, :failure?
    assert plan.reload.status_authorized?

    execution = Minecraft::ExecuteWorldRestore.call(
      plan: plan,
      actor: @actor,
      authorization_token: token,
      confirmation: confirmation
    )
    assert_predicate execution, :success?
    operation = execution.value.fetch(:operation)
    plan.reload
    assert plan.status_queued?
    assert plan.authorization_consumed_at?
    assert plan.pre_restore_world_backup.status_queued?
    assert_equal "world_restore_execute", operation.operation_type
    assert_equal @backup.manifest_digest,
      operation.request_payload.dig("shared_payload", "backup_manifest_digest")
    assert_empty operation.request_payload.dig("shared_payload").keys &
      Minecraft::EnqueueNodeOperation::FORBIDDEN_WORLD_PAYLOAD_KEYS

    blocked_start = Minecraft::EnqueueNodeTask.call(
      node: @node,
      server: @server,
      task_type: "start_instance"
    )
    assert_predicate blocked_start, :failure?
    assert @server.reload.process_state_stopped?

    target_result = completed_restore_result(plan)
    reconciled = Minecraft::ReconcileWorldOperation.call(
      operation: operation,
      action: :target_result,
      target_result: target_result
    )
    assert_predicate reconciled, :success?
    plan.reload
    assert plan.status_completed?
    assert_equal "completed", plan.result_summary.fetch("phase")
    assert plan.pre_restore_world_backup.reload.status_available?
    assert_equal 1, plan.events.where(event_type: "minecraft.world_restore.completed").count

    event_count = plan.events.count
    repeated = Minecraft::ReconcileWorldOperation.call(
      operation: operation,
      action: :target_result,
      target_result: target_result
    )
    assert_predicate repeated, :success?
    assert_equal event_count, plan.events.reload.count
  end

  test "capability, path, immutable contract, and start gates fail closed" do
    assert @node.supports_managed_world_backups_v2?
    assert @node.supports_world_restore_v2?
    @node.metadata["operation_capabilities"]["world_restore_execute"]["unknown_flag"] = true
    assert_not @node.supports_world_restore_v2?
    @node.metadata["operation_capabilities"]["world_restore_execute"].delete("unknown_flag")

    %w[../world /world C:/world world\\region world:stream CON 世界].each do |path|
      assert_predicate Minecraft::WorldPathPolicy.call(path), :failure?, path
    end

    @backup.manifest_digest = "f" * 64
    assert_not @backup.valid?
    assert @backup.errors.of_kind?(:base, :immutable)

    plan = plan_restore
    @server.working_directory = "/srv/minecraft/changed"
    assert_not @server.valid?
    assert @server.errors.of_kind?(:base, :world_restore_active)
  end

  test "a downgraded heartbeat cannot retain stale world safety capability" do
    result = Minecraft::RecordNodeHeartbeat.call(
      node: @node,
      payload: {
        "hostname" => "legacy-node",
        "metadata" => {
          "node_protocol_versions" => [ 1 ],
          "operation_types" => [ "collect_metrics" ]
        }
      }
    )

    assert_predicate result, :success?
    @node.reload
    assert_not @node.supports_managed_world_backups_v2?
    assert_not @node.supports_world_restore_v2?
    assert_equal({}, @node.metadata["operation_capabilities"])
    assert_equal true, @node.metadata["world_restore_recovery_required"]
  end

  test "a proven archive integrity failure quarantines the selected backup" do
    planned = Minecraft::PlanWorldRestore.call(
      server: @server,
      backup: @backup,
      actor: @actor,
      reason: "Validate backup quarantine",
      request_id: SecureRandom.uuid
    )
    plan = planned.value.fetch(:plan)
    authorization = Minecraft::AuthorizeWorldRestore.call(
      plan: plan,
      actor: @actor,
      password: "password123"
    )
    execution = Minecraft::ExecuteWorldRestore.call(
      plan: plan,
      actor: @actor,
      authorization_token: authorization.value.fetch(:authorization_token),
      confirmation: authorization.value.fetch(:confirmation)
    )
    operation = execution.value.fetch(:operation)
    now = Time.current.utc.iso8601(6)
    failed_result_class = Struct.new(:result, :error_code, keyword_init: true) do
      def status_completed?
        false
      end
    end
    target_result = failed_result_class.new(
      error_code: "archive_digest_mismatch",
      result: {
        "restore" => {
          "plan_id" => plan.public_id,
          "phase" => "accepted",
          "rolled_back" => false,
          "recovery_required" => false,
          "error_code" => "archive_digest_mismatch",
          "started_at" => now,
          "completed_at" => now
        }
      }
    )

    reconciled = Minecraft::ReconcileWorldOperation.call(
      operation: operation,
      action: :target_result,
      target_result: target_result
    )

    assert_predicate reconciled, :success?
    assert plan.reload.status_failed?
    assert @backup.reload.status_quarantined?
    assert_equal "archive_digest_mismatch", @backup.error_code
    assert plan.pre_restore_world_backup.reload.status_failed?
  end

  test "expired plans cannot be reported as idempotently executed" do
    plan = plan_restore
    plan.update_columns(
      status: "expired",
      authorization_digest: Digest::SHA256.hexdigest("stale-token"),
      authorization_consumed_at: nil
    )

    result = Minecraft::ExecuteWorldRestore.call(
      plan: plan.reload,
      actor: @actor,
      authorization_token: "stale-token",
      confirmation: Minecraft::PlanWorldRestore.confirmation_for(plan)
    )

    assert_predicate result, :failure?
    assert_equal :world_restore_plan_not_authorized, result.code
    assert_nil plan.reload.node_operation
  end

  private

  def plan_restore
    result = Minecraft::PlanWorldRestore.call(
      server: @server,
      backup: @backup.reload,
      actor: @actor,
      reason: "Immutable target contract",
      request_id: SecureRandom.uuid
    )
    assert_predicate result, :success?
    result.value.fetch(:plan)
  end

  def create_available_backup
    Minecraft::WorldBackup.create!(
      server: @server,
      node: @node,
      created_by: @actor,
      purpose: "manual",
      status: "available",
      request_id: SecureRandom.uuid,
      request_digest: "a" * 64,
      manifest_version: 1,
      safety_profile: Minecraft::WorldBackupManifest::SAFETY_PROFILE,
      archive_format: Minecraft::WorldBackupManifest::ARCHIVE_FORMAT,
      manifest_digest: "b" * 64,
      archive_sha256: "c" * 64,
      archive_bytes: 1,
      uncompressed_bytes: 0,
      entry_count: 0,
      verified_at: Time.current,
      manifest_summary: {
        "world_relative_path" => "world",
        "source_process_state" => "stopped",
        "source_world_state" => "present"
      }
    )
  end

  def completed_restore_result(plan)
    pre_backup = plan.pre_restore_world_backup
    now = Time.current.utc.iso8601(6)
    result_class = Struct.new(:result, :error_code, keyword_init: true) do
      def status_completed?
        true
      end
    end
    result_class.new(
      error_code: nil,
      result: {
        "restore" => {
          "plan_id" => plan.public_id,
          "phase" => "completed",
          "installed_manifest_digest" => plan.backup_manifest_digest,
          "rolled_back" => false,
          "recovery_required" => false,
          "started_at" => now,
          "completed_at" => now,
          "pre_restore_backup" => {
            "manifest_version" => 1,
            "safety_profile" => Minecraft::WorldBackupManifest::SAFETY_PROFILE,
            "backup_id" => pre_backup.public_id,
            "server_id" => @server.public_id,
            "node_id" => @node.public_id,
            "purpose" => "pre_restore",
            "request_digest" => plan.plan_digest,
            "created_at" => now,
            "archive_format" => Minecraft::WorldBackupManifest::ARCHIVE_FORMAT,
            "archive_sha256" => "d" * 64,
            "manifest_digest" => "e" * 64,
            "archive_bytes" => 1,
            "uncompressed_bytes" => 1,
            "entry_count" => 1,
            "world_relative_path" => "world",
            "source_process_state" => "stopped",
            "source_world_state" => "present"
          }
        }
      }
    )
  end

  def world_safety_metadata
    common = {
      "protocol_version" => 2,
      "manifest_versions" => [ 1 ],
      "archive_formats" => [ "tar.gz" ],
      "safety_profile" => Minecraft::WorldBackupManifest::SAFETY_PROFILE
    }
    {
      "node_protocol_versions" => [ 1, 2 ],
      "operation_types" => %w[collect_metrics sync_files world_backup_create world_restore_execute],
      "world_restore_recovery_required" => false,
      "operation_capabilities" => {
        "world_backup_create" => common.merge(
          "stopped_source_required" => true,
          "managed_storage" => true
        ),
        "world_restore_execute" => common.merge(
          "safe_extract" => true,
          "same_filesystem_atomic_swap" => true,
          "pre_restore_snapshot" => true,
          "durable_ledger" => true,
          "crash_recovery" => true,
          "rollback" => true,
          "local_limits" => {
            "max_archive_bytes" => 64.gigabytes,
            "max_manifest_bytes" => 256.megabytes,
            "max_uncompressed_bytes" => 256.gigabytes,
            "max_file_bytes" => 64.gigabytes,
            "max_entries" => 2_000_000,
            "max_directories" => 1_000_000,
            "max_depth" => 64,
            "max_path_bytes" => 1_024,
            "max_expansion_ratio" => 200
          }
        )
      }
    }
  end
end
