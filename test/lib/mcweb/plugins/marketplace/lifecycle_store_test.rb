# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/marketplace/lifecycle_store"

class Mcweb::Plugins::Marketplace::LifecycleStoreTest < ActiveSupport::TestCase
  setup do
    PluginLifecycleStep.delete_all
    PluginLifecycleRun.delete_all
    PluginInstallation.delete_all
    @now = Time.zone.parse("2026-07-29 12:00:00")
    @store = Mcweb::Plugins::Marketplace::LifecycleStore.new(
      clock: -> { @now }
    )
  end

  test "records a versioned lifecycle run and ordered idempotent checkpoints" do
    actor = create_user
    run = @store.start!(
      operation_id: "operation-1",
      action: "install",
      actor:
    )
    @store.bind!(
      run:,
      plugin_id: "acme/demo",
      action: "install",
      to_version: "1.0.0"
    )
    @store.checkpoint!(
      run:,
      step_key: "package_validated",
      details: { digest: "a" * 64 }
    )
    @store.checkpoint!(run:, step_key: "generation_activated")
    @store.finish!(
      run:,
      succeeded: true,
      plugin_id: "acme/demo",
      version: "1.0.0"
    )

    assert_equal "succeeded", run.reload.state
    assert_equal actor, run.actor
    assert_equal %w[package_validated generation_activated],
                 run.steps.pluck(:step_key)
    assert_equal [ 0, 1 ], run.steps.pluck(:sequence)
    assert_equal 2, run.steps.pluck(:idempotency_key).uniq.length

    installation = PluginInstallation.find_by!(plugin_id: "acme/demo")
    assert_equal "enabled", installation.current_state
    assert_equal "enabled", installation.desired_state
    assert_equal "1.0.0", installation.current_version
    assert_equal "operation-1", installation.last_operation_id
  end

  test "database state rejects concurrent administrators for the same plugin" do
    @store.start!(
      operation_id: "operation-1",
      action: "upgrade",
      plugin_id: "acme/demo"
    )

    error = assert_raises(Mcweb::Plugins::Marketplace::LifecycleError) do
      @store.start!(
        operation_id: "operation-2",
        action: "disable",
        plugin_id: "acme/demo"
      )
    end

    assert_includes error.message, "already running"
    assert_equal [ "operation-1" ], PluginLifecycleRun.pluck(:operation_id)
    assert_equal "upgrading",
                 PluginInstallation.find_by!(plugin_id: "acme/demo").current_state
  end

  test "failure is redacted and leaves an explicit retryable recovery state" do
    run = @store.start!(
      operation_id: "operation-1",
      action: "enable",
      plugin_id: "acme/demo"
    )

    @store.finish!(
      run:,
      succeeded: false,
      plugin_id: "acme/demo",
      error: RuntimeError.new("token=never-store")
    )

    run.reload
    installation = run.plugin_installation.reload
    assert_equal "failed", run.state
    assert run.retryable
    assert_equal "failed", installation.current_state
    assert_includes run.error_message, "token=[REDACTED]"
    refute_includes run.error_message, "never-store"

    retry_run = @store.start!(
      operation_id: "operation-2",
      action: "enable",
      plugin_id: "acme/demo"
    )
    assert_equal "running", retry_run.state
  end

  test "stale in-flight runs become explicit interrupted recovery records" do
    run = @store.start!(
      operation_id: "operation-1",
      action: "uninstall",
      plugin_id: "acme/demo"
    )
    run.update!(started_at: @now - 1.hour)

    assert_equal [ run.id ], @store.recover_stale!(before: @now - 30.minutes)

    assert_equal "interrupted", run.reload.state
    assert_equal "lifecycle_interrupted", run.error_code
    installation = run.plugin_installation.reload
    assert_equal "failed", installation.current_state
    assert_equal "lifecycle_interrupted", installation.error_code
  end
end
