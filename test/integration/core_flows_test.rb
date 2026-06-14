# frozen_string_literal: true

require "test_helper"

class Website::BlockSanitizerTest < ActiveSupport::TestCase
  test "strips script tags" do
    html = '<p>Hello</p><script>alert(1)</script>'
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
end
