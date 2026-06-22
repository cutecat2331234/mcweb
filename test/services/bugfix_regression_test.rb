# frozen_string_literal: true

require "test_helper"

class Commerce::IncrementStockTest < ActiveSupport::TestCase
  test "increments stock under row lock" do
    product = Commerce::Product.create!(
      public_id: "prod_inc_#{SecureRandom.hex(4)}",
      name: "Locked stock",
      slug: "locked-stock-#{SecureRandom.hex(3)}",
      product_type: "digital",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 2
    )

    result = Commerce::IncrementStock.call(target: product, quantity: 3)
    assert result.success?
    assert_equal 5, product.reload.stock
  end
end

class Minecraft::ValidateSyncFileUrlTest < ActiveSupport::TestCase
  test "allows signed sync path on public https host" do
    result = Minecraft::ValidateSyncFileUrl.call(url: "https://example.com/minecraft/sync/abc123")
    assert result.success?
  end

  test "allows loopback http sync url" do
    result = Minecraft::ValidateSyncFileUrl.call(url: "http://127.0.0.1:3000/minecraft/sync/abc123")
    assert result.success?
  end

  test "rejects non-sync paths" do
    result = Minecraft::ValidateSyncFileUrl.call(url: "https://example.com/evil")
    assert result.failure?
  end
end

class IntegrationActionRunnerAcquireTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "does not auto-requeue failed integration events" do
    event_id = "evt-failed-#{SecureRandom.hex(4)}"
    Minecraft::IntegrationActionLog.create!(
      event_key: "player.join",
      event_id: event_id,
      payload: {},
      status: "failed",
      error_message: "boom"
    )

    result = Minecraft::Integration::ActionRunner.acquire_or_enqueue(
      event_key: "player.join",
      event_id: event_id,
      payload: {}
    )

    assert result.success?
    assert result.value[:skipped]
    assert_equal "failed", Minecraft::IntegrationActionLog.find_by!(event_id: event_id).status
    assert_no_enqueued_jobs only: Minecraft::RunIntegrationActionJob
  end
end

class Minecraft::HmacReplayGuardTest < ActiveSupport::TestCase
  setup do
    @memory_cache = ActiveSupport::Cache::MemoryStore.new
    Minecraft::HmacReplayGuard.cache_store = @memory_cache
  end

  teardown do
    Minecraft::HmacReplayGuard.cache_store = nil
  end

  test "detects duplicate signatures within ttl" do
    scope = "node:test"
    signature = "abc123"

    assert_not Minecraft::HmacReplayGuard.replayed?(scope: scope, signature: signature, expires_in: 1.minute)
    assert Minecraft::HmacReplayGuard.replayed?(scope: scope, signature: signature, expires_in: 1.minute)
  end
end

class IntegrationActionIdempotentRetryTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @uuid = "550e8400-e29b-41d4-a716-446655440021"
    profile = Minecraft::PlayerProfile.create!
    Minecraft::PlayerIdentity.create!(
      player_profile: profile,
      external_uuid: @uuid,
      username: "RetryUser",
      platform: "java",
      valid_from: Time.current
    )
    Minecraft::IdentityLink.create!(player_profile: profile, user: @user, linked_at: Time.current)
    @rule = Minecraft::IntegrationAction.create!(
      name: "Idempotent retry",
      event_key: "player.join",
      conditions: {},
      actions: [
        { "type" => "set_profile_field", "field_key" => "retry_flag", "value" => "yes" },
        { "type" => "create_notification", "title" => "Welcome", "body" => "joined" }
      ],
      enabled: true
    )
    @event_id = "evt-idem-#{SecureRandom.hex(4)}"
    @tracker = Minecraft::Integration::EffectTracker.new(
      log: Minecraft::IntegrationActionLog.new(event_id: @event_id),
      event_id: @event_id
    )
    @first_effect = @tracker.fingerprint(rule: @rule, action: @rule.actions[0], index: 0)
  end

  test "partial retry skips completed effects" do
    Minecraft::IntegrationActionLog.create!(
      event_key: "player.join",
      event_id: @event_id,
      payload: {},
      status: "failed",
      error_message: "boom",
      completed_effects: [ @first_effect ]
    )

    payload = { "uuid" => @uuid, "platform" => "java", "username" => "RetryUser" }

    assert_difference -> { Notification.count }, 1 do
      result = Minecraft::Integration::ActionRunner.call(
        event_key: "player.join",
        event_id: @event_id,
        payload: payload
      )
      assert result.success?, result.error
    end

    log = Minecraft::IntegrationActionLog.find_by!(event_id: @event_id)
    assert_equal "completed", log.status
    assert_includes log.completed_effects, @first_effect
    assert_equal 2, log.completed_effects.size

    log.update!(status: "failed", error_message: "retry again")
    assert_no_difference -> { Notification.count } do
      assert Minecraft::Integration::ActionRunner.call(
        event_key: "player.join",
        event_id: @event_id,
        payload: payload
      ).success?
    end
  end
end

class IntegrationActionPendingEffectsTest < ActiveSupport::TestCase
  test "marks failed when notification cannot be delivered" do
    uuid = "550e8400-e29b-41d4-a716-446655440022"
    Minecraft::PlayerRef.resolve(uuid: uuid, platform: "java", username: "Unlinked")

    Minecraft::IntegrationAction.create!(
      name: "Notify only",
      event_key: "player.join",
      conditions: {},
      actions: [ { "type" => "create_notification", "title" => "Hi", "body" => "joined" } ],
      enabled: true
    )

    event_id = "evt-pending-#{SecureRandom.hex(4)}"
    result = Minecraft::Integration::ActionRunner.call(
      event_key: "player.join",
      event_id: event_id,
      payload: { "uuid" => uuid, "platform" => "java", "username" => "Unlinked" }
    )

    assert result.failure?
    log = Minecraft::IntegrationActionLog.find_by!(event_id: event_id)
    assert_equal "failed", log.status
    assert_includes log.error_message, "pending effects"
    assert_equal 0, Notification.count
  end

  test "reclaims stale processing logs" do
    event_id = "evt-stale-#{SecureRandom.hex(4)}"
    log = Minecraft::IntegrationActionLog.create!(
      event_key: "player.join",
      event_id: event_id,
      payload: {},
      status: "processing",
      updated_at: 20.minutes.ago
    )

    Minecraft::IntegrationAction.create!(
      name: "Stale retry",
      event_key: "player.join",
      conditions: {},
      actions: [ { "type" => "set_profile_field", "field_key" => "x", "value" => "1" } ],
      enabled: true
    )

    result = Minecraft::Integration::ActionRunner.call(
      event_key: "player.join",
      event_id: event_id,
      payload: {}
    )

    assert result.failure?
    assert_equal "failed", log.reload.status
  end
end

class MinecraftNodeEventsPollTest < ActionDispatch::IntegrationTest
  setup do
    @node = Minecraft::Node.create!(name: "Events Node", status: :online)
    @secret = @node.generate_node_secret!
  end

  test "returns tasks_available when wake timestamp is newer than since" do
    @node.update!(tasks_wake_at: Time.current)

    get "/minecraft/nodes/#{@node.public_id}/events",
        params: { since: 1.minute.ago.iso8601 },
        headers: node_headers("")

    assert_response :success
    assert_equal "tasks_available", response.parsed_body["event"]
    assert response.parsed_body["wake_at"].present?
  end

  test "returns no content when no urgent tasks" do
    @node.update!(tasks_wake_at: 1.hour.ago)

    get "/minecraft/nodes/#{@node.public_id}/events",
        params: { since: Time.current.iso8601 },
        headers: node_headers("")

    assert_response :no_content
  end

  test "invalid since parameter does not error" do
    @node.update!(tasks_wake_at: nil)

    get "/minecraft/nodes/#{@node.public_id}/events",
        params: { since: "not-a-timestamp" },
        headers: node_headers("")

    assert_response :no_content
  end

  private

  def node_headers(payload)
    timestamp = Time.current.to_i.to_s
    signature = OpenSSL::HMAC.hexdigest("SHA256", @secret, "#{timestamp}.#{payload}")
    {
      "X-Node-Timestamp" => timestamp,
      "X-Node-Signature" => signature
    }
  end
end

class ConnectorEventsEventIdTest < ActionDispatch::IntegrationTest
  setup do
    @secret = "connector_secret_#{SecureRandom.hex(16)}"
    @server = Minecraft::Server.create!(
      public_id: "srv_evt_#{SecureRandom.hex(4)}",
      name: "Event Server",
      connector_secret: @secret
    )
  end

  test "events require event_id" do
    payload = {
      event: "player.join",
      payload: {}
    }.to_json

    post "/minecraft/connector/#{@server.public_id}/events",
         params: payload,
         headers: connector_headers(payload)

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["error"], "event_id"
  end

  private

  def connector_headers(payload)
    timestamp = Time.current.to_i.to_s
    signature = OpenSSL::HMAC.hexdigest("SHA256", @secret, "#{timestamp}.#{payload}")
    {
      "CONTENT_TYPE" => "application/json",
      "X-Connector-Timestamp" => timestamp,
      "X-Connector-Signature" => signature
    }
  end
end
