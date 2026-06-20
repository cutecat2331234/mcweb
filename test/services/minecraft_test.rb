# frozen_string_literal: true

require "test_helper"

class Minecraft::ServerProcessStateTest < ActiveSupport::TestCase
  test "process_running? reflects process_state enum" do
    server = Minecraft::Server.create!(
      public_id: "srv_proc_#{SecureRandom.hex(4)}",
      name: "Process State",
      port: 25565
    )

    server.update!(process_state: :stopped)
    assert_not server.process_running?

    server.update!(process_state: :running)
    assert server.process_running?
    assert server.process_state_running?
  end
end

class Minecraft::GenerateLinkCodeTest < ActiveSupport::TestCase
  setup do
    @server = Minecraft::Server.create!(
      public_id: "srv_test1",
      name: "Test Server",
      connector_secret: "test_secret_#{SecureRandom.hex(16)}"
    )
  end

  test "generates expiring link code" do
    uuid = "550e8400-e29b-41d4-a716-446655440000"
    ensure_connector_player_session!(server: @server, uuid: uuid, username: "Steve")

    result = Minecraft::GenerateLinkCode.call(
      server: @server,
      minecraft_uuid: uuid,
      minecraft_username: "Steve",
      identity_type: "java"
    )

    assert result.success?
    assert result.value[:code].present?
    assert result.value[:link_code].expires_at > Time.current
  end

  test "rejects link code when player is not on server" do
    result = Minecraft::GenerateLinkCode.call(
      server: @server,
      minecraft_uuid: "550e8400-e29b-41d4-a716-446655440099",
      minecraft_username: "Steve",
      identity_type: "java"
    )

    assert_not result.success?
  end
end

class Minecraft::CompleteLinkTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @server = Minecraft::Server.create!(
      public_id: "srv_test2",
      name: "Test Server 2",
      connector_secret: "test_secret_#{SecureRandom.hex(16)}"
    )
    uuid = "550e8400-e29b-41d4-a716-446655440001"
    ensure_connector_player_session!(server: @server, uuid: uuid, username: "Alex")
    gen = Minecraft::GenerateLinkCode.call(
      server: @server,
      minecraft_uuid: uuid,
      minecraft_username: "Alex",
      identity_type: "java"
    )
    @code = gen.value[:code]
  end

  test "binds minecraft identity to user" do
    result = Minecraft::CompleteLink.call(user: @user, code: @code)
    assert result.success?
    identity = Minecraft::Identity.find_by(user: @user)
    assert_equal "550e8400-e29b-41d4-a716-446655440001", identity.uuid
  end

  test "rejects expired code reuse" do
    Minecraft::CompleteLink.call(user: @user, code: @code)
    other_user = create_user
    result = Minecraft::CompleteLink.call(user: other_user, code: @code)
    assert result.failure?
  end
end

class Minecraft::ConnectorAuthenticatorTest < ActiveSupport::TestCase
  setup do
  @secret = "connector_secret_#{SecureRandom.hex(16)}"
    @server = Minecraft::Server.create!(
      public_id: "srv_auth1",
      name: "Auth Server",
      connector_secret: @secret
    )
  end

  test "validates correct signature" do
    timestamp = Time.current.to_i.to_s
    payload = '{"status":"ok"}'
    signature = OpenSSL::HMAC.hexdigest("SHA256", @secret, "#{timestamp}.#{payload}")

    result = Minecraft::ConnectorAuthenticator.call(
      server: @server,
      payload: payload,
      signature: signature,
      timestamp: timestamp
    )

    assert result.success?
  end

  test "rejects invalid signature" do
    result = Minecraft::ConnectorAuthenticator.call(
      server: @server,
      payload: "{}",
      signature: "invalid",
      timestamp: Time.current.to_i.to_s
    )

    assert result.failure?
  end

  test "rejects missing timestamp" do
    payload = '{"status":"ok"}'
    signature = OpenSSL::HMAC.hexdigest("SHA256", @secret, payload)

    result = Minecraft::ConnectorAuthenticator.call(
      server: @server,
      payload: payload,
      signature: signature,
      timestamp: nil
    )

    assert result.failure?
    assert_match(/timestamp|时间戳/i, result.error)
  end
end
