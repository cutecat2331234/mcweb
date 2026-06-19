# frozen_string_literal: true

require "test_helper"

class Minecraft::PlayerRefTest < ActiveSupport::TestCase
  test "resolve creates profile and identity" do
    ref = Minecraft::PlayerRef.resolve(
      uuid: "550e8400-e29b-41d4-a716-446655440099",
      platform: "java",
      username: "Notch"
    )

    assert ref.public_id.present?
    assert_equal "Notch", ref.username
    assert_equal "550e8400-e29b-41d4-a716-446655440099", ref.active_uuid
  end

  test "resolve returns same profile for same uuid" do
    first = Minecraft::PlayerRef.resolve(uuid: "550e8400-e29b-41d4-a716-446655440098", platform: "java", username: "A")
    second = Minecraft::PlayerRef.resolve(uuid: "550e8400-e29b-41d4-a716-446655440098", platform: "java", username: "A")
    assert_equal first.public_id, second.public_id
  end
end

class Minecraft::ConnectorApiV2Test < ActionDispatch::IntegrationTest
  setup do
    @secret = "connector_secret_#{SecureRandom.hex(16)}"
    @server = Minecraft::Server.create!(
      public_id: "srv_v2_#{SecureRandom.hex(4)}",
      name: "V2 Server",
      connector_secret: @secret
    )
  end

  test "link_codes endpoint returns code and player_id" do
    payload = {
      uuid: "550e8400-e29b-41d4-a716-446655440010",
      username: "Steve",
      platform: "java"
    }.to_json

    post "/minecraft/connector/#{@server.public_id}/link_codes",
         params: payload,
         headers: connector_headers(payload)

    assert_response :success
    body = JSON.parse(response.body)
    assert body["code"].present?
    assert body["player_id"].present?
  end

  test "heartbeat records snapshot" do
    payload = {
      online_players: 3,
      max_players: 20,
      tps: 19.8,
      version: "1.20.4"
    }.to_json

    assert_difference -> { Minecraft::ServerSnapshot.count }, 1 do
      post "/minecraft/connector/#{@server.public_id}/heartbeat",
           params: payload,
           headers: connector_headers(payload)
    end

    assert_response :success
  end

  test "config endpoint returns skin mode" do
    get "/minecraft/connector/#{@server.public_id}/config",
        headers: connector_headers("")

    assert_response :success
    body = JSON.parse(response.body)
    assert body["skin_mode"].present?
  end

  test "whois endpoint returns linked player info" do
    user = create_user(username: "steve_web")
    player_ref = Minecraft::PlayerRef.resolve(
      uuid: "550e8400-e29b-41d4-a716-446655440011",
      platform: "java",
      username: "Steve"
    )
    player_ref.link_user!(user)

    payload = { uuid: "550e8400-e29b-41d4-a716-446655440011", platform: "java" }.to_json
    post "/minecraft/connector/#{@server.public_id}/whois",
         params: payload,
         headers: connector_headers(payload)

    assert_response :success
    body = JSON.parse(response.body)
    assert body["linked"]
    assert_equal "steve_web", body["website_username"]
  end

  test "config endpoint returns task handlers" do
    get "/minecraft/connector/#{@server.public_id}/config",
        headers: connector_headers("")

    assert_response :success
    body = JSON.parse(response.body)
    assert body["task_handlers"]["broadcast_announcement"].present?
  end

  test "config endpoint parses link command" do
    SiteSetting.set("minecraft.link_command", "/mcweb bind")
    get "/minecraft/connector/#{@server.public_id}/config",
        headers: connector_headers("")

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "/mcweb bind", body["link_command"]
    assert_equal "mcweb", body["command_root"]
    assert_equal "bind", body["link_subcommand"]
  ensure
    SiteSetting.set("minecraft.link_command", "/website link")
  end

  test "events endpoint triggers integration runner" do
    Minecraft::IntegrationAction.create!(
      name: "Welcome join",
      event_key: "player.join",
      conditions: {},
      actions: [ { "type" => "set_profile_field", "field_key" => "last_join", "value" => "yes" } ],
      enabled: true
    )

    event_id = "evt-#{SecureRandom.hex(4)}"
    payload = {
      event: "player.join",
      event_id: event_id,
      uuid: "550e8400-e29b-41d4-a716-446655440020",
      username: "Joiner",
      platform: "java",
      payload: {}
    }.to_json

    post "/minecraft/connector/#{@server.public_id}/events",
         params: payload,
         headers: connector_headers(payload)

    assert_response :success
    assert Minecraft::IntegrationActionLog.exists?(event_id: event_id)
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

class Minecraft::EnqueueBroadcastTest < ActiveSupport::TestCase
  setup do
    @server = Minecraft::Server.create!(
      public_id: "srv_broadcast_#{SecureRandom.hex(4)}",
      name: "Broadcast Server",
      connector_secret: "secret_#{SecureRandom.hex(8)}",
      status: :online
    )
  end

  test "enqueue broadcast creates connector task" do
    assert_difference -> { Minecraft::ConnectorTask.count }, 1 do
      result = Minecraft::EnqueueBroadcast.call(message: "Hello everyone", title: "Test")
      assert result.success?
    end

    task = Minecraft::ConnectorTask.last
    assert_equal "broadcast_announcement", task.task_type
    assert_equal "Hello everyone", task.payload["message"]
  end
end

class Minecraft::RefreshSkinTest < ActiveSupport::TestCase
  test "updates skin from mojang textures payload" do
    profile = Minecraft::PlayerProfile.create!
    uuid = "550e8400-e29b-41d4-a716-446655440055"
    Minecraft::PlayerIdentity.create!(
      player_profile: profile,
      platform: "java",
      external_uuid: uuid,
      username: "Steve",
      identity_type: "primary",
      valid_from: Time.current
    )

    service = Minecraft::RefreshSkin.new(uuid: uuid, platform: "java")
    service.define_singleton_method(:fetch_mojang_textures) do |_uuid|
      { texture_url: "http://example.com/skin.png", skin_model: "slim" }
    end
    result = service.call
    assert result.success?, result.error

    identity = Minecraft::PlayerIdentity.find_by!(external_uuid: uuid)
    assert_equal "http://example.com/skin.png", identity.skin_texture_url
    assert_equal "slim", identity.skin_model
  end
end

class Minecraft::ApplyPermissionGroupMappingsTest < ActiveSupport::TestCase
  test "applies role when game group matches" do
    user = create_user
    role = Role.find_or_create_by!(key: "vip") { |r| r.name = "VIP" }
    SiteSetting.set("minecraft.permission_group_mappings", [ { "game_group" => "vip", "role_key" => "vip" } ].to_json)

    profile = Minecraft::PlayerProfile.create!
    Minecraft::PermissionGroup.create!(
      player_profile: profile,
      group_key: "vip",
      group_label: "VIP",
      source: "luckperms"
    )
    Minecraft::IdentityLink.create!(player_profile: profile, user: user, linked_at: Time.current)

    result = Minecraft::ApplyPermissionGroupMappings.call(user: user, player_profile: profile)
    assert result.success?
    assert user.roles.exists?(id: role.id)
  end
end

class Identity::AccountAccessTest < ActiveSupport::TestCase
  test "staff requires module grants for admin access" do
    user = create_user
    user.update!(account_type: :staff)
    grant_permission(user, "admin.access")

    assert_not Identity::AccountAccess.can_access_admin?(user)

    user.admin_module_grants.create!(module_key: "forum", granted_at: Time.current)
    assert Identity::AccountAccess.can_access_admin?(user)
  end

  test "owner can access admin" do
    user = create_user
    user.update!(account_type: :owner)
    grant_permission(user, "admin.access")
    assert Identity::AccountAccess.can_access_admin?(user)
  end
end
