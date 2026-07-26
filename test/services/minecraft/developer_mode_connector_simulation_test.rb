# frozen_string_literal: true

require "test_helper"

class Minecraft::DeveloperModeConnectorSimulationTest < ActiveSupport::TestCase
  setup do
    @server = Minecraft::Server.create!(
      name: "Developer Mode connector",
      status: :offline,
      connector_secret: "secret_#{SecureRandom.hex(16)}"
    )
  end

  test "console commands complete locally without an online connector" do
    with_unrestricted_developer_mode do
      result = Minecraft::EnqueueConsoleCommand.call(
        server: @server,
        command: "say simulated"
      )

      assert result.success?
      assert result.value[:simulated]
      task = result.value.fetch(:task).reload
      assert_predicate task, :completed?
      assert_equal true, task.result.fetch("simulated")
      assert_equal true, task.result.fetch("developer_mode")
    end
  end

  test "all connector task creation paths are simulated by the model boundary" do
    task = nil
    with_unrestricted_developer_mode do
      task = Minecraft::ConnectorTask.create!(
        server: @server,
        task_type: "broadcast_announcement",
        delivery_id: "dev-#{SecureRandom.uuid}",
        status: "pending",
        payload: { message: "local only" }
      )
    end

    assert_predicate task.reload, :completed?
    assert_equal true, task.result.fetch("simulated")
    assert_not Minecraft::ConnectorTask.where(id: task.id, status: "pending").exists?
  end

  test "polling never exposes pre-existing pending commands" do
    task = Minecraft::ConnectorTask.create!(
      server: @server,
      task_type: "run_commands",
      delivery_id: "pending-#{SecureRandom.uuid}",
      status: "pending",
      payload: { commands: [ "op someone" ] }
    )

    with_unrestricted_developer_mode do
      result = Minecraft::TaskDispatcher.call(server: @server, action: :claim)

      assert result.success?
      assert_empty result.value.fetch(:tasks)
      assert_equal 1, result.value.fetch(:simulated)
    end

    assert_predicate task.reload, :completed?
    assert_equal true, task.result.fetch("developer_mode")
  end

  test "normal mode keeps connector tasks pending for the real connector" do
    task = Minecraft::ConnectorTask.create!(
      server: @server,
      task_type: "run_commands",
      status: "pending",
      payload: { commands: [ "say real connector" ] }
    )

    assert_predicate task, :pending?
  end

  private

  def with_unrestricted_developer_mode
    settings = Mcweb::DeveloperMode.parse(
      config: {
        developer_mode: {
          enabled: true,
          preset: "unrestricted"
        }
      },
      environment: {}
    )
    previous_settings = Mcweb::DeveloperMode.instance_variable_get(:@settings)
    Mcweb::DeveloperMode.instance_variable_set(:@settings, settings)
    yield
  ensure
    Mcweb::DeveloperMode.instance_variable_set(:@settings, previous_settings)
  end
end
