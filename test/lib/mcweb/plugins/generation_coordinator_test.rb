# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/generation_coordinator"

class Mcweb::Plugins::GenerationCoordinatorTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    PluginProcessAck.delete_all
    PluginGeneration.delete_all
    @now = Time.zone.parse("2026-07-29 10:00:00")
    @runtime = { "acme/demo" => "1.0.0" }
    @reloads = 0
    @coordinator = coordinator("web-a")
  end

  test "publishes a desired generation and activates it after a healthy acknowledgement" do
    generation = nil
    assert_enqueued_with(job: PluginGenerationMonitorJob) do
      generation = @coordinator.publish!(
        desired_plugins: @runtime,
        previous_plugins: {},
        action: "install",
        target_plugin_id: "acme/demo",
        operation_id: "operation-1",
        timeout: 10.seconds
      )
    end

    assert_equal "active", generation.state
    assert_equal 1, generation.number
    assert_equal({ "acme/demo" => "1.0.0" }, generation.desired_plugins)
    assert_equal 1, @reloads
    ack = generation.process_acks.sole
    assert_equal "web-a", ack.process_uid
    assert_equal "healthy", ack.status
    assert_equal({ "acme/demo" => "1.0.0" }, ack.plugin_versions)
  end

  test "waits for all snapshotted processes before activating" do
    prior = PluginGeneration.create!(
      number: 1,
      state: "active",
      action: "boot",
      desired_plugins: @runtime,
      previous_plugins: {},
      expected_process_uids: %w[web-a worker-a],
      minimum_ack_ratio: 1,
      deadline_at: @now + 1.hour,
      activated_at: @now
    )
    PluginProcessAck.create!(
      plugin_generation: prior,
      process_uid: "worker-a",
      process_kind: "worker",
      status: "healthy",
      plugin_versions: @runtime,
      acked_at: @now,
      last_seen_at: @now
    )
    @runtime["acme/demo"] = "2.0.0"

    generation = @coordinator.publish!(
      desired_plugins: @runtime,
      previous_plugins: { "acme/demo" => "1.0.0" },
      action: "upgrade",
      timeout: 10.seconds
    )

    assert_equal "pending", generation.state
    assert_equal %w[web-a worker-a], generation.expected_process_uids

    worker = coordinator("worker-a", kind: "worker")
    worker.reconcile!(generation:, process_kind: "worker")

    assert_equal "active", generation.reload.state
    assert_equal "superseded", prior.reload.state
  end

  test "two web processes and one worker converge on the same generation" do
    prior = PluginGeneration.create!(
      number: 1,
      state: "active",
      action: "boot",
      desired_plugins: @runtime,
      previous_plugins: {},
      expected_process_uids: %w[web-a web-b worker-a],
      minimum_ack_ratio: 1,
      deadline_at: @now + 1.hour,
      activated_at: @now
    )
    [
      [ "web-b", "web", 102 ],
      [ "worker-a", "worker", 202 ]
    ].each do |uid, kind, pid|
      PluginProcessAck.create!(
        plugin_generation: prior,
        process_uid: uid,
        process_kind: kind,
        process_pid: pid,
        hostname: "#{uid}.example.test",
        status: "healthy",
        plugin_versions: @runtime,
        acked_at: @now,
        last_seen_at: @now
      )
    end
    @runtime["acme/demo"] = "2.0.0"

    generation = @coordinator.publish!(
      desired_plugins: @runtime,
      previous_plugins: { "acme/demo" => "1.0.0" },
      action: "upgrade",
      timeout: 10.seconds
    )

    assert_equal "pending", generation.state
    assert_equal %w[web-a web-b worker-a], generation.expected_process_uids

    coordinator("web-b").reconcile!(generation:, process_kind: "web")
    assert_equal "pending", generation.reload.state

    coordinator("worker-a", kind: "worker").reconcile!(
      generation:,
      process_kind: "worker"
    )

    assert_equal "active", generation.reload.state
    assert_equal(
      {
        "web-a" => "web",
        "web-b" => "web",
        "worker-a" => "worker"
      },
      generation.process_acks.order(:process_uid).to_h do |ack|
        [ ack.process_uid, ack.process_kind ]
      end
    )
  end

  test "a failed process acknowledgement publishes the previous generation as rollback" do
    @runtime = { "acme/demo" => "2.0.0" }
    bad = coordinator("web-a", catalog: -> { [ plugin_row("acme/demo", "broken") ] })

    generation = bad.publish!(
      desired_plugins: @runtime,
      previous_plugins: { "acme/demo" => "1.0.0" },
      action: "upgrade",
      timeout: 10.seconds
    )

    assert_equal "rolled_back", generation.state
    rollback = PluginGeneration.find_by!(parent_generation: generation, action: "rollback")
    assert_equal({ "acme/demo" => "1.0.0" }, rollback.desired_plugins)
    assert_equal "failed", rollback.state
    assert_equal "generation_mismatch", rollback.process_acks.sole.error_code
  end

  test "a timed out generation rolls back instead of remaining mixed indefinitely" do
    generation = PluginGeneration.create!(
      number: 1,
      state: "pending",
      action: "enable",
      desired_plugins: @runtime,
      previous_plugins: {},
      expected_process_uids: %w[web-a worker-a],
      minimum_ack_ratio: 1,
      deadline_at: @now - 1.second
    )

    @coordinator.finalize!(generation.id)

    assert_equal "rolled_back", generation.reload.state
    rollback = PluginGeneration.find_by!(parent_generation: generation, action: "rollback")
    assert_equal({}, rollback.desired_plugins)
  end

  private

  def coordinator(uid, kind: "web", catalog: nil)
    Mcweb::Plugins::GenerationCoordinator.new(
      clock: -> { @now },
      reloader: -> { @reloads += 1 },
      runtime_catalog: catalog || -> { @runtime.map { |id, version| plugin_row(id, version) } },
      process_uid: uid,
      process_kind: kind,
      hostname: "#{kind}.example.test",
      pid: kind == "worker" ? 202 : 101
    )
  end

  def plugin_row(id, version)
    { id:, version:, status: "active" }
  end
end
