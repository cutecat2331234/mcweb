# frozen_string_literal: true

require "test_helper"

class Minecraft::GracefulStopServerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    SiteSetting.set("minecraft.graceful_stop.enabled", "true")
    @node = Minecraft::Node.create!(name: "Grace Node", status: :online)
    @server = Minecraft::Server.create!(
      name: "Survival",
      node: @node,
      process_driver: "script",
      process_config: { "start" => "./start.sh", "stop" => "./stop.sh" },
      working_directory: "/opt/mc",
      status: :online,
      last_heartbeat_at: Time.current,
      connector_secret: "secret_#{SecureRandom.hex(8)}"
    )
  end

  test "queues connector tasks and delayed stop when connector online" do
    assert_difference -> { Minecraft::ConnectorTask.count }, 2 do
      assert_enqueued_jobs 1, only: Minecraft::EnqueueStopInstanceJob do
        result = Minecraft::GracefulStopServer.call(server: @server)
        assert result.success?
        assert result.value[:graceful]
        assert_equal 35, result.value[:delay_seconds]
      end
    end

    types = Minecraft::ConnectorTask.where(server: @server).order(:created_at).pluck(:task_type)
    assert_equal %w[broadcast_announcement run_commands], types
  end

  test "queues immediate stop when graceful stop disabled" do
    @server.update!(metadata: { "graceful_stop_enabled" => false })

    assert_no_difference -> { Minecraft::ConnectorTask.count } do
      result = Minecraft::GracefulStopServer.call(server: @server)
      assert result.success?
      assert_not result.value[:graceful]
    end

    assert_equal "stop_instance", @server.node_tasks.last.task_type
  end

  test "queues immediate stop when connector offline" do
    @server.update!(status: :offline, last_heartbeat_at: 10.minutes.ago)

    assert_no_difference -> { Minecraft::ConnectorTask.count } do
      assert_enqueued_jobs 1, only: Minecraft::EnqueueStopInstanceJob do
        result = Minecraft::GracefulStopServer.call(server: @server)
        assert result.success?
        assert_equal 0, result.value[:delay_seconds]
      end
    end
  end
end

class Minecraft::SyncInstanceReportTest < ActiveSupport::TestCase
  setup do
    @node = Minecraft::Node.create!(name: "Metrics Node", status: :online)
    @server = Minecraft::Server.create!(
      name: "Lobby",
      node: @node,
      process_driver: "script"
    )
  end

  test "stores metrics and process state from node report" do
    metrics = {
      "host" => { "cpu_percent" => 12.5, "memory_percent" => 45.0 },
      "instance" => { "process_state" => "running" }
    }

    result = Minecraft::SyncInstanceReport.call(
      node: @node,
      server: @server,
      payload: { "metrics" => metrics, "process_state" => "running" }
    )

    assert result.success?
    @server.reload
    assert_equal metrics, @server.metadata["last_metrics"]
    assert @server.metadata["last_metrics_at"].present?
    assert_equal "running", @server.process_state
  end

  test "rejects report from wrong node" do
    other = Minecraft::Node.create!(name: "Other", status: :offline)
    result = Minecraft::SyncInstanceReport.call(
      node: other,
      server: @server,
      payload: { "metrics" => { "host" => {} } }
    )

    assert result.failure?
  end
end

class Minecraft::NodeTaskResultPersistenceTest < ActiveSupport::TestCase
  setup do
    @node = Minecraft::Node.create!(name: "Task Node", status: :online)
    @server = Minecraft::Server.create!(name: "Exec", node: @node, process_driver: "script")
    @task = Minecraft::NodeTask.create!(
      node: @node,
      server: @server,
      task_type: "exec_command",
      status: "claimed",
      delivery_id: SecureRandom.uuid,
      payload: { "command" => "echo hi" }
    )
  end

  test "complete preserves stdout and stderr in result jsonb" do
    result_payload = {
      "success" => true,
      "status" => "completed",
      "stdout" => "hi\n",
      "stderr" => ""
    }

    dispatch = Minecraft::NodeTaskDispatcher.call(
      node: @node,
      task: @task,
      result: result_payload,
      action: :complete
    )

    assert dispatch.success?
    stored = @task.reload.result
    assert_equal "hi\n", stored["stdout"]
    assert_equal "", stored["stderr"]
  end

  test "collect_metrics syncs metrics to server metadata" do
    task = Minecraft::NodeTask.create!(
      node: @node,
      server: @server,
      task_type: "collect_metrics",
      status: "claimed",
      delivery_id: SecureRandom.uuid,
      payload: {}
    )
    metrics = { "host" => { "cpu_percent" => 5.0 } }

    Minecraft::NodeTaskDispatcher.call(
      node: @node,
      task: task,
      result: { "success" => true, "status" => "completed", "metrics" => metrics, "process_state" => "running" },
      action: :complete
    )

    @server.reload
    assert_equal metrics, @server.metadata["last_metrics"]
    assert_equal "running", @server.process_state
  end
end

class Minecraft::EnsureInstanceRunningJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    @node = Minecraft::Node.create!(name: "Warm Node", status: :online)
    @server = Minecraft::Server.create!(
      name: "Survival",
      public_id: "srv_warm_#{SecureRandom.hex(4)}",
      node: @node,
      process_driver: "script",
      process_state: :stopped
    )
    @order = Commerce::Order.create!(
      public_id: "ord_warm_#{SecureRandom.hex(6)}",
      order_number: "WRM#{SecureRandom.hex(4)}",
      user: @user,
      status: "paid",
      subtotal_cents: 500,
      total_cents: 500,
      currency: "CNY"
    )
    @item = Commerce::OrderItem.create!(
      order: @order,
      product_name: "Kit",
      unit_price_cents: 500,
      quantity: 1,
      total_cents: 500,
      fulfillment_snapshot: { fulfillment_config: { server_id: @server.public_id } }
    )
    @fulfillment = Commerce::Fulfillment.create!(
      order: @order,
      order_item: @item,
      delivery_id: "dlv_#{SecureRandom.alphanumeric(16)}",
      status: "pending"
    )
  end

  test "enqueues start_instance without fixed delay job" do
    assert_no_enqueued_jobs(only: Minecraft::ChainFulfillmentAfterStartJob) do
      assert_difference -> { Minecraft::NodeTask.count }, 1 do
        Minecraft::EnsureInstanceRunningJob.perform_now(@fulfillment.id)
      end
    end
  end

  test "polls when instance already starting" do
    @server.update!(process_state: :starting)

    assert_enqueued_with(job: Minecraft::PollInstanceProcessStateJob, args: [ @server.id ]) do
      Minecraft::EnsureInstanceRunningJob.perform_now(@fulfillment.id)
    end
  end
end

class Minecraft::ServerRecentNodeTasksTest < ActiveSupport::TestCase
  test "recent_node_tasks returns latest tasks" do
    node = Minecraft::Node.create!(name: "Recent", status: :offline)
    server = Minecraft::Server.create!(name: "S", node: node, process_driver: "script")

    base = Time.current
    3.times do |i|
      Minecraft::NodeTask.create!(
        node: node,
        server: server,
        task_type: "exec_command",
        status: "completed",
        delivery_id: "dlv_#{i}_#{SecureRandom.hex(4)}",
        payload: {},
        created_at: base - i.minutes
      )
    end

    assert_equal 2, server.recent_node_tasks(2).count
    assert_equal 3, server.recent_node_tasks.count
  end
end

class Minecraft::ReconcileProcessStateJobTest < ActiveSupport::TestCase
  setup do
    @admin = create_user
    grant_permission(@admin, "minecraft.servers.manage")
    @node = Minecraft::Node.create!(name: "Reconcile Node", status: :online)
    @server = Minecraft::Server.create!(
      name: "Mismatch",
      node: @node,
      process_driver: "script",
      status: :online,
      last_heartbeat_at: Time.current,
      process_state: :stopped
    )
  end

  test "notifies staff on process mismatch" do
    assert_difference -> { Notification.where(user: @admin).count }, 1 do
      Minecraft::ReconcileProcessStateJob.perform_now
    end

    notification = Notification.where(user: @admin).order(:id).last
    assert_equal "minecraft.process_mismatch", notification.notification_type
  end
end
