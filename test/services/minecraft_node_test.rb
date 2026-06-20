# frozen_string_literal: true

require "test_helper"

class Minecraft::EnqueueNodeTaskTest < ActiveSupport::TestCase
  setup do
    @node = Minecraft::Node.create!(name: "Test Node", status: :offline)
    @server = Minecraft::Server.create!(
      name: "Survival",
      node: @node,
      process_driver: "script",
      process_config: { "start" => "./start.sh", "stop" => "./stop.sh" },
      working_directory: "/opt/mc"
    )
  end

  test "creates start_instance task with process payload" do
    result = Minecraft::EnqueueNodeTask.call(
      node: @node,
      server: @server,
      task_type: "start_instance"
    )

    assert result.success?
    task = result.value[:task]
    assert_equal "start_instance", task.task_type
    assert_equal "script", task.payload["process_driver"]
    assert_equal "starting", @server.reload.process_state
  end

  test "rejects task when server not on node" do
    other = Minecraft::Node.create!(name: "Other", status: :offline)
    result = Minecraft::EnqueueNodeTask.call(
      node: other,
      server: @server,
      task_type: "start_instance"
    )

    assert result.failure?
  end
end

class Minecraft::ManagePlayerSessionsTest < ActiveSupport::TestCase
  setup do
    @server = Minecraft::Server.create!(name: "Lobby", status: :online)
    @profile = Minecraft::PlayerProfile.create!
    Minecraft::PlayerIdentity.create!(
      player_profile: @profile,
      external_uuid: SecureRandom.uuid,
      username: "Steve",
      platform: "java",
      valid_from: Time.current
    )
  end

  test "opens session on join and closes on quit" do
    Minecraft::ManagePlayerSessions.call(
      server: @server,
      player_profile: @profile,
      username: "Steve",
      event: "player.join"
    )
    assert_equal 1, Minecraft::PlayerSession.active.count

    Minecraft::ManagePlayerSessions.call(
      server: @server,
      player_profile: @profile,
      username: "Steve",
      event: "player.quit"
    )
    assert_equal 0, Minecraft::PlayerSession.active.count
  end
end

class Minecraft::NodeAuthenticatorTest < ActiveSupport::TestCase
  test "validates hmac signature" do
    node = Minecraft::Node.create!(name: "Node")
    secret = node.generate_node_secret!
    payload = '{"ok":true}'
    ts = Time.current.to_i
    sig = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{ts}.#{payload}")

    result = Minecraft::NodeAuthenticator.call(
      node: node,
      payload: payload,
      signature: sig,
      timestamp: ts
    )

    assert result.success?
  end
end

class Minecraft::ChainFulfillmentAfterStartJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    @node = Minecraft::Node.create!(name: "Chain Node", status: :online)
    @server = Minecraft::Server.create!(
      name: "Survival",
      public_id: "srv_chain_#{SecureRandom.hex(4)}",
      node: @node,
      process_driver: "script",
      process_state: :running,
      status: :online
    )
    @order = Commerce::Order.create!(
      public_id: "ord_chain_#{SecureRandom.hex(6)}",
      order_number: "CHN#{SecureRandom.hex(4)}",
      user: @user,
      status: "paid",
      subtotal_cents: 500,
      total_cents: 500,
      currency: "CNY"
    )
    @item = Commerce::OrderItem.create!(
      order: @order,
      product_name: "VIP Kit",
      unit_price_cents: 500,
      quantity: 1,
      total_cents: 500,
      fulfillment_snapshot: {
        fulfillment_config: {
          server_id: @server.public_id,
          commands: [ "give {player} diamond 1" ]
        }
      }
    )
    @fulfillment = Commerce::Fulfillment.create!(
      order: @order,
      order_item: @item,
      delivery_id: "dlv_#{SecureRandom.alphanumeric(16)}",
      status: "pending"
    )
  end

  test "queues pending fulfillments for server after instance start" do
    assert_enqueued_with(job: Minecraft::DispatchFulfillmentJob, args: [ @fulfillment.id ]) do
      Minecraft::ChainFulfillmentAfterStartJob.perform_now(@server.id)
    end
  end

  test "pending_fulfillments_for reads server id from fulfillment_config" do
    matches = Minecraft::ChainFulfillmentAfterStartJob.pending_fulfillments_for(@server)
    assert_includes matches.pluck(:id), @fulfillment.id
  end
end

class Commerce::MembershipTypeCommandTest < ActiveSupport::TestCase
  test "lp timed mode generates addtemp grant command" do
    type = Commerce::MembershipType.new(
      slug: "timed-vip",
      name: "Timed VIP",
      duration_mode: "fixed_days",
      duration_days: 30,
      game_permission_mode: "lp_timed"
    )

    assert_includes type.default_grant_commands.first, "addtemp"
    assert_includes type.default_grant_commands.first, "30d"
  end
end
