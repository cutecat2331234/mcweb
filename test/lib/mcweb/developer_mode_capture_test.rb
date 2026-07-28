# frozen_string_literal: true

require "test_helper"

class Mcweb::DeveloperModeCaptureTest < ActiveSupport::TestCase
  test "captures a filtered webhook record on local disk" do
    root = Pathname(Dir.mktmpdir)
    now = Time.utc(2026, 7, 26, 12, 34, 56)

    response = Mcweb::DeveloperModeCapture.capture_webhook!(
      uri: URI.parse(
        "http://127.0.0.1:4567/services/hooks/path-token-secret?token=top-secret&view=full"
      ),
      body: {
        event: "topic.created",
        password: "body-secret",
        authorization_token: "signed-adjustment-secret",
        confirmation: "typed-adjustment-secret"
      }.to_json,
      headers: {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer header-secret",
        "X-McWeb-Signature" => "signature-secret"
      },
      root: root,
      now: now
    )

    assert_equal "202", response.code
    response_body = JSON.parse(response.body)
    assert_equal true, response_body.fetch("captured")
    assert response_body.fetch("capture_id").present?

    path = root.join("tmp/developer-mode/webhooks/2026-07-26.jsonl")
    assert_predicate path, :file?
    entry = JSON.parse(path.read)

    assert_equal "topic.created", entry.dig("payload", "event")
    assert_equal "[FILTERED]", entry.dig("payload", "password")
    assert_equal "[FILTERED]", entry.dig("payload", "authorization_token")
    assert_equal "[FILTERED]", entry.dig("payload", "confirmation")
    assert_equal "[FILTERED]", entry.dig("headers", "Authorization")
    assert_equal "[FILTERED]", entry.dig("headers", "X-McWeb-Signature")
    assert_equal "application/json", entry.dig("headers", "Content-Type")
    assert_includes entry.fetch("url"), "/__filtered__"
    assert_includes entry.fetch("url"), "token=%5BFILTERED%5D"
    assert_includes entry.fetch("url"), "view=full"
    assert_not_includes path.read, "path-token-secret"
    assert_not_includes path.read, "top-secret"
    assert_not_includes path.read, "body-secret"
    assert_not_includes path.read, "signed-adjustment-secret"
    assert_not_includes path.read, "typed-adjustment-secret"
    assert_not_includes path.read, "header-secret"
    assert_not_includes path.read, "signature-secret"
  ensure
    root&.rmtree if root&.exist?
  end

  test "non json payloads are represented by size and digest only" do
    root = Pathname(Dir.mktmpdir)

    Mcweb::DeveloperModeCapture.capture_webhook!(
      uri: URI.parse("http://localhost/hook"),
      body: "plain secret payload",
      headers: {},
      root: root,
      now: Time.utc(2026, 7, 26)
    )

    entry = JSON.parse(
      root.join("tmp/developer-mode/webhooks/2026-07-26.jsonl").read
    )
    assert_equal "plain secret payload".bytesize,
      entry.dig("payload", "body_bytes")
    assert_equal Digest::SHA256.hexdigest("plain secret payload"),
      entry.dig("payload", "body_sha256")
    assert_not_includes entry.to_json, "plain secret payload"
  ensure
    root&.rmtree if root&.exist?
  end

  test "captures filtered web push records without persisting subscription secrets" do
    root = Pathname(Dir.mktmpdir)
    now = Time.utc(2026, 7, 26, 13, 45, 12)
    endpoint = "https://push.example.test/send/top-secret-endpoint"

    capture = Mcweb::DeveloperModeCapture.capture_web_push!(
      notification_id: 42,
      notification_type: "forum.mention",
      user_id: 7,
      subscription_id: 11,
      endpoint: endpoint,
      payload: {
        title: "Mention",
        body: "A safe preview",
        token: "payload-token-secret",
        auth: "payload-auth-secret",
        private_key: "payload-private-key"
      }.to_json,
      root: root,
      now: now
    )

    assert capture.capture_id.present?
    path = root.join("tmp/developer-mode/web-push/2026-07-26.jsonl")
    assert_equal path, capture.path
    assert_predicate path, :file?

    entry = JSON.parse(path.read)
    assert_equal capture.capture_id, entry.fetch("id")
    assert_equal 42, entry.dig("notification", "id")
    assert_equal "forum.mention", entry.dig("notification", "type")
    assert_equal 7, entry.dig("notification", "user_id")
    assert_equal 11, entry.dig("subscription", "id")
    assert_equal Digest::SHA256.hexdigest(endpoint),
      entry.dig("subscription", "endpoint_sha256")
    assert_equal "Mention", entry.dig("payload", "title")
    assert_equal "[FILTERED]", entry.dig("payload", "token")
    assert_equal "[FILTERED]", entry.dig("payload", "auth")
    assert_equal "[FILTERED]", entry.dig("payload", "private_key")
    assert_not_includes path.read, endpoint
    assert_not_includes path.read, "payload-token-secret"
    assert_not_includes path.read, "payload-auth-secret"
    assert_not_includes path.read, "payload-private-key"
  ensure
    root&.rmtree if root&.exist?
  end
end
