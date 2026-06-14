# frozen_string_literal: true

require "test_helper"

class Minecraft::GenerateLinkCodeTest < ActiveSupport::TestCase
  setup do
    @server = Minecraft::Server.create!(
      public_id: "srv_test1",
      name: "Test Server",
      connector_secret: "test_secret_#{SecureRandom.hex(16)}"
    )
  end

  test "generates expiring link code" do
    result = Minecraft::GenerateLinkCode.call(
      server: @server,
      minecraft_uuid: "550e8400-e29b-41d4-a716-446655440000",
      minecraft_username: "Steve",
      identity_type: "java"
    )

    assert result.success?
    assert result.value[:code].present?
    assert result.value[:link_code].expires_at > Time.current
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
    gen = Minecraft::GenerateLinkCode.call(
      server: @server,
      minecraft_uuid: "550e8400-e29b-41d4-a716-446655440001",
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
end
