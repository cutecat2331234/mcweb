# frozen_string_literal: true

require "test_helper"

class Website::BlockSanitizerTest < ActiveSupport::TestCase
  test "strips script tags" do
    html = "<p>Hello</p><script>alert(1)</script>"
    result = Website::BlockSanitizer.call(html: html)
    assert result.success?
    assert_not_includes result.value.to_s, "script"
    assert_includes result.value.to_s, "Hello"
  end

  test "strips event handlers" do
    html = '<a href="/" onclick="evil()">link</a>'
    result = Website::BlockSanitizer.call(html: html)
    assert result.success?
    assert_not_includes result.value.to_s, "onclick"
  end
end

class InstallationLockTest < ActiveSupport::TestCase
  test "setup lock prevents reopening" do
    InstallationLock.unlock!
    user = create_user
    assert_not InstallationLock.locked?
    InstallationLock.lock!(user: user)
    assert InstallationLock.locked?
  end
end

class Payments::WebhookProcessorTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_webhook1",
      order_number: "ORD-WH-001",
      user: @user,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      discount_cents: 0,
      currency: "CNY"
    )
    @payment = Payments::Record.create!(
      order: @order,
      provider: "fake",
      status: "pending",
      amount_cents: 1000,
      currency: "CNY",
      provider_payment_id: "fake_pay_wh"
    )
  end

  test "processes webhook with valid signature" do
    payload = { payment_id: "fake_pay_wh" }.to_json
    signature = OpenSSL::HMAC.hexdigest("SHA256", "fake_webhook_secret", payload)

    result = Payments::WebhookProcessor.call(
      provider: "fake",
      event_id: "evt_1",
      event_type: "payment.succeeded",
      payload: payload,
      signature: signature
    )

    assert result.success?
    assert_equal "succeeded", @payment.reload.status
  end

  test "duplicate webhook is idempotent" do
    payload = { payment_id: "fake_pay_wh" }.to_json
    signature = OpenSSL::HMAC.hexdigest("SHA256", "fake_webhook_secret", payload)
    args = { provider: "fake", event_id: "evt_dup", event_type: "payment.succeeded", payload: payload, signature: signature }
    Payments::WebhookProcessor.call(**args)
    result = Payments::WebhookProcessor.call(**args)
    assert result.success?
    assert result.value[:idempotent]
  end

  test "reclaims stale processing webhook events" do
    payload = { payment_id: "fake_pay_wh" }.to_json
    signature = OpenSSL::HMAC.hexdigest("SHA256", "fake_webhook_secret", payload)
    event = Payments::WebhookEvent.create!(
      provider: "fake",
      event_id: "evt_stale",
      event_type: "payment.succeeded",
      payload: JSON.parse(payload),
      status: "processing",
      updated_at: 10.minutes.ago
    )

    result = Payments::WebhookProcessor.call(
      provider: "fake",
      event_id: event.event_id,
      event_type: "payment.succeeded",
      payload: payload,
      signature: signature
    )

    assert result.success?
    assert_equal "processed", event.reload.status
    assert_equal "succeeded", @payment.reload.status
  end

  test "stripe ignores non-payment webhook events" do
    Payments::ProviderConfig.create!(
      provider: "stripe",
      enabled: true,
      credentials: { "webhook_secret" => "whsec_test" }
    )
    payload = {
      type: "charge.refunded",
      data: { object: { id: "ch_123", metadata: { payment_record_id: @payment.id.to_s } } }
    }.to_json
    signature = OpenSSL::HMAC.hexdigest("SHA256", "whsec_test", payload)

    result = Payments::WebhookProcessor.call(
      provider: "stripe",
      event_id: "evt_refund",
      event_type: "charge.refunded",
      payload: payload,
      signature: signature
    )

    assert result.success?
    assert_equal "pending", @payment.reload.status
  end
end

class Minecraft::IntegrationActionRunnerRetryTest < ActiveSupport::TestCase
  test "retries failed integration event" do
    Minecraft::IntegrationAction.create!(
      name: "Retry test",
      event_key: "player.join",
      conditions: {},
      actions: [ { "type" => "set_profile_field", "field_key" => "retry_flag", "value" => "yes" } ],
      enabled: true
    )
    event_id = "evt-retry-#{SecureRandom.hex(4)}"
    Minecraft::IntegrationActionLog.create!(
      event_key: "player.join",
      event_id: event_id,
      payload: {},
      status: "failed",
      error_message: "boom"
    )

    result = Minecraft::Integration::ActionRunner.call(
      event_key: "player.join",
      event_id: event_id,
      payload: { "uuid" => "550e8400-e29b-41d4-a716-446655440099", "platform" => "java" }
    )

    assert result.success?, result.error
    assert_equal "completed", Minecraft::IntegrationActionLog.find_by!(event_id: event_id).status
  end
end
