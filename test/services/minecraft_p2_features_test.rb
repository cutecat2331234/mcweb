# frozen_string_literal: true

require "test_helper"

class Minecraft::P2FeaturesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @node = Minecraft::Node.create!(name: "P2 Node", status: :online, last_heartbeat_at: Time.current)
    @server = Minecraft::Server.create!(
      name: "P2 Survival",
      node: @node,
      process_driver: "script",
      process_config: { "start" => "./start.sh", "stop" => "./stop.sh" },
      working_directory: "/opt/mc",
      status: :online,
      last_heartbeat_at: Time.current,
      connector_secret: "secret_#{SecureRandom.hex(8)}"
    )
  end

  test "ValidateExecCommand allows when prefix matches" do
    SiteSetting.set("minecraft.exec_command.allowed_prefixes", "ls,tail")
    assert Minecraft::ValidateExecCommand.call(command: "ls -la").success?
    assert Minecraft::ValidateExecCommand.call(command: "rm -rf /").failure?
  end

  test "ValidateExecCommand allows all when empty whitelist in non production with env opt-in" do
    SiteSetting.set("minecraft.exec_command.allowed_prefixes", "")
    previous = ENV["MCWEB_ALLOW_UNRESTRICTED_EXEC_COMMAND"]
    ENV["MCWEB_ALLOW_UNRESTRICTED_EXEC_COMMAND"] = "1"
    assert Minecraft::ValidateExecCommand.call(command: "anything").success?
  ensure
    if previous.nil?
      ENV.delete("MCWEB_ALLOW_UNRESTRICTED_EXEC_COMMAND")
    else
      ENV["MCWEB_ALLOW_UNRESTRICTED_EXEC_COMMAND"] = previous
    end
  end

  test "ValidateExecCommand rejects empty whitelist in non production by default" do
    SiteSetting.set("minecraft.exec_command.allowed_prefixes", "")
    previous = ENV["MCWEB_ALLOW_UNRESTRICTED_EXEC_COMMAND"]
    ENV.delete("MCWEB_ALLOW_UNRESTRICTED_EXEC_COMMAND")
    result = Minecraft::ValidateExecCommand.call(command: "anything")
    assert result.failure?
    assert_includes result.error, "not configured"
  ensure
    if previous.nil?
      ENV.delete("MCWEB_ALLOW_UNRESTRICTED_EXEC_COMMAND")
    else
      ENV["MCWEB_ALLOW_UNRESTRICTED_EXEC_COMMAND"] = previous
    end
  end

  test "ValidateExecCommand rejects empty whitelist in production" do
    SiteSetting.set("minecraft.exec_command.allowed_prefixes", "")
    production_env = ActiveSupport::EnvironmentInquirer.new("production")
    singleton = class << Rails; self; end
    original_env = Rails.env
    singleton.define_method(:env) { production_env }
    begin
      result = Minecraft::ValidateExecCommand.call(command: "anything")
      assert result.failure?
      assert_includes result.error, "not configured"
    ensure
      singleton.define_method(:env) { original_env }
    end
  end

  test "EnqueueConsoleCommand creates run_commands connector task" do
    assert_difference -> { Minecraft::ConnectorTask.count }, 1 do
      result = Minecraft::EnqueueConsoleCommand.call(server: @server, command: "say hi")
      assert result.success?
    end
    assert_equal "run_commands", Minecraft::ConnectorTask.last.task_type
  end

  test "RecordServerAudit creates audit log" do
    user = create_user
    assert_difference -> { AuditLog.count }, 1 do
      Minecraft::RecordServerAudit.call(action: "minecraft.server.start", actor: user, server: @server)
    end
  end

  test "GeneratePairingToken and PairNode exchange secret" do
    gen = Minecraft::GeneratePairingToken.call(node: @node)
    assert gen.success?

    result = Minecraft::PairNode.call(token: gen.value[:token], hostname: "node-host")
    assert result.success?
    assert_equal @node.public_id, result.value[:node_id]
    assert result.value[:node_secret].present?
    @node.reload
    assert_nil @node.metadata["pairing_token"]
  end

  test "SuggestLeastLoadedNode picks node with fewest servers" do
    node_b = Minecraft::Node.create!(name: "Heavy", status: :online, last_heartbeat_at: Time.current)
    Minecraft::Server.create!(name: "S2", node: node_b, port: 25566)
    Minecraft::Server.create!(name: "S3", node: node_b, port: 25567)

    result = Minecraft::SuggestLeastLoadedNode.call
    assert result.success?
    assert_equal @node.id, result.value[:node].id
  end

  test "RecordNodeMetricSnapshot stores host metrics" do
    assert_difference -> { Minecraft::NodeMetricSnapshot.count }, 1 do
      result = Minecraft::RecordNodeMetricSnapshot.call(
        node: @node,
        host_metrics: { "cpu_percent" => 12.5, "mem_used_bytes" => 1_000_000 }
      )
      assert result.success?
    end
  end

  test "MaintenanceActive detects server maintenance status" do
    @server.update!(status: :maintenance)
    result = Minecraft::MaintenanceActive.call(server: @server)
    assert result.value[:active]
  end

  test "EnqueueNodeTask accepts backup_world and sync_files" do
    %w[backup_world restore_world].each do |task_type|
      result = Minecraft::EnqueueNodeTask.call(
        node: @node,
        server: @server,
        task_type: task_type,
        payload: { destination: "/tmp/x" }
      )
      assert result.success?, "expected success for #{task_type}"
    end

    sync_result = Minecraft::EnqueueNodeTask.call(
      node: @node,
      server: @server,
      task_type: "sync_files",
      payload: {
        url: "http://127.0.0.1:3000/minecraft/sync/test-token",
        destination: "/tmp/x"
      }
    )
    assert sync_result.success?
  end

  test "ScheduleCollectMetricsJob enqueues metrics tasks" do
    assert_difference -> { Minecraft::NodeTask.where(task_type: "collect_metrics").count }, 1 do
      Minecraft::ScheduleCollectMetricsJob.perform_now
    end
  end

  test "BuildFileSyncUrl generates verifiable url" do
    path = "storage/test.txt"
    FileUtils.mkdir_p(Rails.root.join("storage"))
    File.write(Rails.root.join(path), "ok")
    result = Minecraft::BuildFileSyncUrl.call(path: path)
    assert result.success?
    assert_includes result.value[:url], "/minecraft/sync/"
  end

  test "BuildFileSyncUrl rejects path traversal" do
    result = Minecraft::BuildFileSyncUrl.call(path: "storage/../../../config/local.yml")
    assert_not result.success?
    assert_match(/not allowed|不允许/i, result.error)
  end
end
