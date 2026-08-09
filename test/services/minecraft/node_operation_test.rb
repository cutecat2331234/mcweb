# frozen_string_literal: true

require "test_helper"

class Minecraft::NodeOperationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    @node = Minecraft::Node.create!(
      name: "Operation Node",
      status: :online,
      metadata: operation_capabilities
    )
    @server_a = create_server("A", @node, "/srv/a")
    @server_b = create_server("B", @node, "/srv/b")
  end

  teardown do
    clear_enqueued_jobs
  end

  test "Sidekiq preparation freezes all child servers into one batch per physical node" do
    result = enqueue_and_prepare(
      servers: [ @server_a, @server_b ],
      idempotency_key: "metrics-operation-1"
    )

    assert result.success?
    operation = result.value.fetch(:operation).reload
    assert operation.status_ready?
    assert_equal 2, operation.target_count
    assert_equal 1, operation.batch_count

    batch = operation.batches.sole
    assert_equal 2, batch.target_count
    assert_equal %w[collect_metrics collect_metrics], batch.payload.fetch("targets").pluck("task_type")
    assert_equal [ @server_a.public_id, @server_b.public_id ].sort,
      batch.payload.fetch("targets").pluck("target_key").sort
  end

  test "idempotency key reuses the same operation and rejects a different request" do
    first = Minecraft::EnqueueNodeOperation.call(
      operation_type: "collect_metrics",
      servers: [ @server_a ],
      idempotency_key: "metrics-idempotent"
    )
    repeated = Minecraft::EnqueueNodeOperation.call(
      operation_type: "collect_metrics",
      servers: [ @server_a ],
      idempotency_key: "metrics-idempotent"
    )
    conflict = Minecraft::EnqueueNodeOperation.call(
      operation_type: "collect_metrics",
      servers: [ @server_b ],
      idempotency_key: "metrics-idempotent"
    )

    assert first.success?
    assert repeated.success?
    assert repeated.value.fetch(:idempotent)
    assert_equal first.value.fetch(:operation).id, repeated.value.fetch(:operation).id
    assert conflict.failure?
    assert_equal 1, Minecraft::NodeOperation.where(idempotency_key: "metrics-idempotent").count
  end

  test "a node cannot receive another batch before result acknowledgement" do
    first = enqueue_and_prepare(servers: [ @server_a ], idempotency_key: "queue-first")
    second = enqueue_and_prepare(servers: [ @server_b ], idempotency_key: "queue-second")

    assert second.value.fetch(:operation).reload.status_queued?
    assert_empty second.value.fetch(:operation).batches

    first_claim = claim(@node)
    assert_equal first.value.fetch(:operation).id, first_claim.operation_id
    blocked_claim = claim(@node)
    assert_nil blocked_claim

    completion = complete_batch(first_claim, [ completed_result(@server_a, metrics: true) ])
    assert completion.success?
    assert_not completion.value.fetch(:acknowledged)
    assert first_claim.reload.status_result_pending_ack?
    assert_nil claim(@node), "result persistence alone must not release the node"

    assert_enqueued_with(job: Minecraft::ReconcileNodeOperationJob, args: [ first_claim.operation_id ]) do
      acknowledgement = acknowledge_batch(first_claim, completion.value.fetch(:acknowledgement_id))
      assert acknowledgement.success?
      assert acknowledgement.value.fetch(:acknowledged)
    end

    wrong_acknowledgement = acknowledge_batch(first_claim, SecureRandom.uuid)
    repeated_acknowledgement = acknowledge_batch(first_claim, completion.value.fetch(:acknowledgement_id))
    conflicting_completion = complete_batch(first_claim, [ failed_result(@server_a) ])
    assert wrong_acknowledgement.failure?
    assert repeated_acknowledgement.success?
    assert repeated_acknowledgement.value.fetch(:idempotent)
    assert conflicting_completion.failure?

    Minecraft::ReconcileNodeOperationJob.perform_now(first_claim.operation_id)
    assert first.value.fetch(:operation).reload.status_completed?
    assert_nil first.value.fetch(:operation).dispatch_slot
    Minecraft::PrepareNodeOperationJob.perform_now

    next_batch = claim(@node)
    assert_equal second.value.fetch(:operation).id, next_batch.operation_id
  end

  test "completion requires a terminal result for every frozen target" do
    operation = enqueue_and_prepare(
      servers: [ @server_a, @server_b ],
      idempotency_key: "complete-every-target"
    ).value.fetch(:operation)
    batch = claim(@node)

    incomplete = complete_batch(batch, [ completed_result(@server_a) ])

    assert incomplete.failure?
    assert batch.reload.status_dispatched?
    assert_empty batch.target_results
    assert_equal 2, operation.reload.target_count
  end

  test "acknowledged target errors complete the parent with errors and preserve metrics" do
    operation = enqueue_and_prepare(
      servers: [ @server_a, @server_b ],
      idempotency_key: "partial-errors"
    ).value.fetch(:operation)
    batch = claim(@node)
    completion = complete_batch(batch, [
      completed_result(@server_a, metrics: true),
      failed_result(@server_b)
    ])
    acknowledge_batch(batch, completion.value.fetch(:acknowledgement_id))

    Minecraft::ReconcileNodeOperationJob.perform_now(operation.id)

    operation.reload
    assert operation.status_completed_with_errors?
    assert_equal 1, operation.completed_target_count
    assert_equal 1, operation.failed_target_count
    assert_equal 12.5, @server_a.reload.metadata.dig("last_metrics", "host", "cpu_percent")
    assert_equal "running", @server_a.process_state
  end

  test "one parent task group waits for every physical node batch" do
    other_node = Minecraft::Node.create!(
      name: "Other Operation Node",
      status: :online,
      metadata: operation_capabilities
    )
    other_server = create_server("C", other_node, "/srv/c")
    operation = enqueue_and_prepare(
      servers: [ @server_a, other_server ],
      idempotency_key: "multi-node-parent"
    ).value.fetch(:operation)

    first_batch = claim(@node)
    first_completion = complete_batch(first_batch, [ completed_result(@server_a) ])
    acknowledge_batch(first_batch, first_completion.value.fetch(:acknowledgement_id))
    Minecraft::ReconcileNodeOperationJob.perform_now(operation.id)
    assert operation.reload.status_running?

    second_batch = claim(other_node)
    second_completion = complete_batch(second_batch, [ completed_result(other_server) ])
    acknowledge_batch(second_batch, second_completion.value.fetch(:acknowledgement_id))
    Minecraft::ReconcileNodeOperationJob.perform_now(operation.id)

    assert operation.reload.status_completed?
    assert_equal 2, operation.completed_target_count
  end

  test "the next task group stays queued until every node in the current group is acknowledged" do
    other_node = Minecraft::Node.create!(
      name: "Serialized Other Node",
      status: :online,
      metadata: operation_capabilities
    )
    other_server = create_server("SerializedC", other_node, "/srv/serialized-c")
    first = enqueue_and_prepare(
      servers: [ @server_a, other_server ],
      idempotency_key: "serialized-parent-first"
    ).value.fetch(:operation)
    second = enqueue_and_prepare(
      servers: [ @server_b ],
      idempotency_key: "serialized-parent-second"
    ).value.fetch(:operation)

    assert_equal 1, first.reload.dispatch_slot
    assert first.status_ready?
    assert second.reload.status_queued?
    assert_nil second.dispatch_slot
    assert_empty second.batches

    first_node_batch = claim(@node)
    first_node_completion = complete_batch(first_node_batch, [ completed_result(@server_a) ])
    acknowledge_batch(first_node_batch, first_node_completion.value.fetch(:acknowledgement_id))
    Minecraft::ReconcileNodeOperationJob.perform_now(first.id)

    assert first.reload.status_running?
    assert_equal 1, first.dispatch_slot
    Minecraft::PrepareNodeOperationJob.perform_now
    assert second.reload.status_queued?
    assert_empty second.batches
    assert_nil claim(@node), "a free node must not start another task group early"

    other_batch = claim(other_node)
    other_completion = complete_batch(other_batch, [ completed_result(other_server) ])
    acknowledge_batch(other_batch, other_completion.value.fetch(:acknowledgement_id))
    assert_enqueued_with(job: Minecraft::PrepareNodeOperationJob, args: []) do
      Minecraft::ReconcileNodeOperationJob.perform_now(first.id)
    end

    assert first.reload.status_completed?
    assert_nil first.dispatch_slot
    Minecraft::PrepareNodeOperationJob.perform_now
    assert second.reload.status_ready?
    assert_equal 1, second.dispatch_slot
    assert_equal second.id, claim(@node).operation_id
  end

  test "sync groups require a verified revision and a safe relative path" do
    valid = Minecraft::EnqueueNodeOperation.call(
      operation_type: "sync_files",
      servers: [ @server_a ],
      payload: {
        url: "http://127.0.0.1:3000/minecraft/sync/token",
        sha256: "a" * 64,
        revision: "plugin-v2",
        relative_path: "plugins/plugin.jar"
      }
    )
    unsafe = Minecraft::EnqueueNodeOperation.call(
      operation_type: "sync_files",
      servers: [ @server_a ],
      payload: {
        url: "http://127.0.0.1:3000/minecraft/sync/token",
        sha256: "a" * 64,
        revision: "plugin-v2",
        relative_path: "../secrets.yml"
      }
    )
    unsafe_override = Minecraft::EnqueueNodeOperation.call(
      operation_type: "sync_files",
      servers: [ @server_a ],
      payload: {
        url: "http://127.0.0.1:3000/minecraft/sync/token",
        sha256: "a" * 64,
        revision: "plugin-v2",
        relative_path: "plugins/plugin.jar"
      },
      target_payloads: {
        @server_a.public_id => { relative_path: "../secrets.yml" }
      }
    )

    assert valid.success?
    assert unsafe.failure?
    assert unsafe_override.failure?
  end

  test "an old node cannot receive a v2 task group before advertising support" do
    old_node = Minecraft::Node.create!(name: "Legacy Node", status: :online)
    old_server = create_server("Legacy", old_node, "/srv/legacy")

    result = Minecraft::EnqueueNodeOperation.call(
      operation_type: "collect_metrics",
      servers: [ old_server ]
    )

    assert result.failure?
    assert_not old_node.supports_operation_batches?
  end

  test "sync completion with the wrong applied revision is recorded as a target error" do
    result = Minecraft::EnqueueNodeOperation.call(
      operation_type: "sync_files",
      servers: [ @server_a ],
      payload: {
        url: "http://127.0.0.1:3000/minecraft/sync/token",
        sha256: "a" * 64,
        revision: "plugin-v2",
        relative_path: "plugins/plugin.jar"
      },
      idempotency_key: "sync-revision-check"
    )
    Minecraft::PrepareNodeOperationJob.perform_now
    batch = claim(@node)

    assert_equal "plugin-v2", batch.payload.dig("shared_payload", "revision")
    assert_nil batch.payload.dig("targets", 0, "payload", "url")

    completion = complete_batch(batch, [
      {
        "target_key" => @server_a.public_id,
        "status" => "completed",
        "applied_revision" => "plugin-v1",
        "result" => { "success" => true, "status" => "completed" }
      }
    ])

    assert completion.success?
    target_result = batch.target_results.sole
    assert target_result.status_failed?
    assert_equal "revision_mismatch", target_result.error_code
  end

  test "scheduled metrics use v1 only for nodes still rolling forward" do
    old_node = Minecraft::Node.create!(name: "Legacy Metrics Node", status: :online)
    old_server = create_server("LegacyMetrics", old_node, "/srv/legacy-metrics")

    assert_difference -> { Minecraft::NodeOperation.count }, 1 do
      assert_difference -> { old_server.node_tasks.where(task_type: "collect_metrics").count }, 1 do
        Minecraft::ScheduleCollectMetricsJob.perform_now
      end
    end
  end

  test "legacy tasks are also claimed one at a time and are never silently reclaimed" do
    first = Minecraft::NodeTask.create!(
      node: @node,
      server: @server_a,
      task_type: "collect_metrics",
      delivery_id: SecureRandom.uuid,
      status: "pending"
    )
    second = Minecraft::NodeTask.create!(
      node: @node,
      server: @server_b,
      task_type: "collect_metrics",
      delivery_id: SecureRandom.uuid,
      status: "pending"
    )

    first_claim = Minecraft::NodeTaskDispatcher.call(node: @node, action: :claim)
    blocked_claim = Minecraft::NodeTaskDispatcher.call(node: @node, action: :claim)

    assert_equal [ first.id ], first_claim.value.fetch(:tasks).map(&:id)
    assert_empty blocked_claim.value.fetch(:tasks)
    assert first.reload.claimed?
    assert second.reload.pending?
  end

  test "legacy and v2 dispatchers share the same per-node execution lock" do
    operation = enqueue_and_prepare(
      servers: [ @server_a ],
      idempotency_key: "shared-execution-lock"
    ).value.fetch(:operation)
    batch = claim(@node)
    legacy = Minecraft::NodeTask.create!(
      node: @node,
      server: @server_b,
      task_type: "collect_metrics",
      delivery_id: SecureRandom.uuid,
      status: "pending"
    )

    legacy_claim = Minecraft::NodeTaskDispatcher.call(node: @node, action: :claim)

    assert_empty legacy_claim.value.fetch(:tasks)
    assert batch.reload.active?
    assert legacy.reload.pending?
    assert operation.reload.status_running?
  end

  private

  def operation_capabilities
    {
      "node_protocol_versions" => [ 1, 2 ],
      "operation_types" => %w[collect_metrics sync_files]
    }
  end

  def create_server(suffix, node, working_directory)
    Minecraft::Server.create!(
      name: "Operation Server #{suffix}",
      public_id: "srv_operation_#{suffix.downcase}_#{SecureRandom.hex(4)}",
      node: node,
      process_driver: "script",
      process_config: { "status" => "true" },
      working_directory: working_directory,
      status: :online
    )
  end

  def enqueue_and_prepare(servers:, idempotency_key:)
    result = Minecraft::EnqueueNodeOperation.call(
      operation_type: "collect_metrics",
      servers: servers,
      idempotency_key: idempotency_key
    )
    Minecraft::PrepareNodeOperationJob.perform_now
    result
  end

  def claim(node)
    result = Minecraft::NodeOperationDispatcher.call(node: node, action: :claim)
    assert result.success?
    result.value.fetch(:batch)
  end

  def complete_batch(batch, target_results)
    Minecraft::NodeOperationDispatcher.call(
      node: batch.node,
      batch_id: batch.public_id,
      action: :complete,
      envelope: {
        delivery_id: batch.delivery_id,
        payload_digest: batch.payload_digest,
        target_results: target_results
      }
    )
  end

  def acknowledge_batch(batch, acknowledgement_id)
    Minecraft::NodeOperationDispatcher.call(
      node: batch.node,
      batch_id: batch.public_id,
      action: :acknowledge,
      envelope: {
        delivery_id: batch.delivery_id,
        payload_digest: batch.payload_digest,
        acknowledgement_id: acknowledgement_id
      }
    )
  end

  def completed_result(server, metrics: false)
    result = { "success" => true, "status" => "completed" }
    if metrics
      result["metrics"] = { "host" => { "cpu_percent" => 12.5 } }
      result["process_state"] = "running"
    end
    {
      "target_key" => server.public_id,
      "status" => "completed",
      "result" => result,
      "completed_at" => Time.current.iso8601
    }
  end

  def failed_result(server)
    {
      "target_key" => server.public_id,
      "status" => "failed",
      "result" => { "success" => false, "status" => "failed" },
      "error_code" => "target_update_failed",
      "error_message" => "test failure",
      "completed_at" => Time.current.iso8601
    }
  end
end
