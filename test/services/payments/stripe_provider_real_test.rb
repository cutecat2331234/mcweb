# frozen_string_literal: true

require "test_helper"

class Payments::StripeProviderRealWebhookTest < ActiveSupport::TestCase
  setup do
    configure_stripe
    @order = Commerce::Order.create!(
      public_id: "ord_stripe_webhook_#{SecureRandom.hex(6)}",
      order_number: "STRIPE-WH-#{SecureRandom.hex(6).upcase}",
      user: create_user,
      status: "awaiting_payment",
      subtotal_cents: 1_250,
      discount_cents: 0,
      total_cents: 1_250,
      currency: "CNY"
    )
    @payment = Payments::Record.create!(
      order: @order,
      provider: "stripe",
      provider_mode: "test",
      status: "pending",
      amount_cents: 1_250,
      currency: "CNY",
      provider_payment_id: "cs_test_#{SecureRandom.hex(8)}"
    )
  end

  test "officially signed paid checkout confirms only the matching server-side amount and currency" do
    payload = stripe_checkout_payload
    result = process_payload(payload)

    assert result.success?, result.error
    assert_equal "succeeded", @payment.reload.status
    assert_equal "pi_test_paid", @payment.metadata["stripe_payment_intent_id"]
    assert @order.reload.paid? || @order.processing? || @order.fulfilled?
  end

  test "amount mismatch is dead-lettered without changing the payment" do
    payload = stripe_checkout_payload(
      object_overrides: { amount_total: @payment.amount_cents + 1 }
    )
    result = process_payload(payload)

    assert result.failure?
    assert_equal "amount_mismatch", result.code
    assert_equal "pending", @payment.reload.status
    assert Payments::WebhookEvent.find_by!(
      provider: "stripe",
      event_id: JSON.parse(payload).fetch("id")
    ).dead_letter?
  end

  test "test and live mode mismatch is rejected" do
    payload = stripe_checkout_payload(object_overrides: { livemode: true })
    result = process_payload(payload)

    assert result.failure?
    assert_equal "environment_mismatch", result.code
    assert_equal "pending", @payment.reload.status
  end

  test "unpaid completed checkout is deferred until the asynchronous success event" do
    payload = stripe_checkout_payload(object_overrides: { payment_status: "unpaid" })
    result = process_payload(payload)

    assert result.success?
    assert result.value[:deferred]
    assert_equal "pending", @payment.reload.status
  end

  test "expired checkout marks only the payment attempt failed and leaves the order payable" do
    payload = stripe_checkout_payload(
      event_type: "checkout.session.expired",
      object_overrides: { payment_status: "unpaid" }
    )
    result = process_payload(payload)

    assert result.success?, result.error
    assert_equal "failed", @payment.reload.status
    assert_equal "awaiting_payment", @order.reload.status
  end

  test "a retryable payment intent failure does not block a later success event" do
    failed_payload = stripe_payment_intent_payload(
      event_type: "payment_intent.payment_failed"
    )
    failed_result = process_payload(failed_payload)

    assert failed_result.success?, failed_result.error
    assert_equal "pending", @payment.reload.status
    assert_equal "pi_test_retryable", @payment.metadata["stripe_payment_intent_id"]

    succeeded_payload = stripe_payment_intent_payload(
      event_type: "payment_intent.succeeded",
      object_overrides: { amount_received: @payment.amount_cents }
    )
    succeeded_result = process_payload(succeeded_payload)

    assert succeeded_result.success?, succeeded_result.error
    assert_equal "succeeded", @payment.reload.status
  end

  private

  def configure_stripe
    Payments::ProviderConfig.find_or_initialize_by(provider: "stripe").tap do |config|
      config.enabled = true
      config.credentials = {
        "secret_key" => "sk_test_real_webhook",
        "webhook_secret" => "whsec_real_webhook"
      }
      config.save!
      mark_stripe_provider_connection_tested!(config)
    end
  end

  def stripe_checkout_payload(event_type: "checkout.session.completed", object_overrides: {})
    object = {
      id: @payment.provider_payment_id,
      object: "checkout.session",
      livemode: false,
      payment_status: "paid",
      amount_total: @payment.amount_cents,
      currency: @payment.currency.downcase,
      client_reference_id: @order.public_id,
      payment_intent: "pi_test_paid",
      metadata: {
        payment_record_id: @payment.id.to_s,
        order_public_id: @order.public_id
      }
    }.merge(object_overrides)

    {
      id: "evt_#{SecureRandom.hex(8)}",
      object: "event",
      type: event_type,
      data: { object: object }
    }.to_json
  end

  def stripe_payment_intent_payload(event_type:, object_overrides: {})
    object = {
      id: "pi_test_retryable",
      object: "payment_intent",
      livemode: false,
      amount: @payment.amount_cents,
      currency: @payment.currency.downcase,
      metadata: {
        payment_record_id: @payment.id.to_s,
        order_public_id: @order.public_id
      }
    }.merge(object_overrides)

    {
      id: "evt_#{SecureRandom.hex(8)}",
      object: "event",
      type: event_type,
      data: { object: object }
    }.to_json
  end

  def process_payload(payload)
    parsed = JSON.parse(payload)
    Payments::WebhookProcessor.call(
      provider: "stripe",
      event_id: parsed.fetch("id"),
      event_type: parsed.fetch("type"),
      payload: payload,
      signature: stripe_webhook_signature(payload, "whsec_real_webhook")
    )
  end
end

class Commerce::StripeRefundRecoveryTest < ActiveSupport::TestCase
  setup do
    configure_stripe
    @admin = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_stripe_refund_#{SecureRandom.hex(6)}",
      order_number: "STRIPE-REF-#{SecureRandom.hex(6).upcase}",
      user: create_user,
      status: "paid",
      subtotal_cents: 2_000,
      discount_cents: 0,
      total_cents: 2_000,
      currency: "CNY"
    )
    @payment = Payments::Record.create!(
      order: @order,
      provider: "stripe",
      provider_mode: "test",
      status: "succeeded",
      amount_cents: 2_000,
      currency: "CNY",
      provider_payment_id: "cs_test_#{SecureRandom.hex(8)}",
      metadata: { "stripe_payment_intent_id" => "pi_test_refundable" }
    )
  end

  test "creates a real provider refund with a stable idempotency key and persists provider state" do
    provider_refund = stripe_refund_response(id: "re_test_created", status: "succeeded")
    client, _, refunds = build_stripe_test_client(created_refund: provider_refund)

    result = with_stripe_client(client) do
      Commerce::ProcessRefund.call(
        order: @order,
        payment_record: @payment,
        amount_cents: @payment.amount_cents,
        reason: "Customer request",
        approved_by: @admin
      )
    end

    assert result.success?, result.error
    refund = @order.refunds.sole
    assert_equal "completed", refund.status
    assert_equal "re_test_created", refund.provider_refund_id
    assert_equal "succeeded", refund.provider_status
    assert_nil refund.processing_started_at
    assert_equal @payment.amount_cents, refunds.create_requests.sole.dig(:params, :amount)
    assert_equal "pi_test_refundable", refunds.create_requests.sole.dig(:params, :payment_intent)
    assert_equal "mcweb:refund:#{refund.id}:v1", refunds.create_requests.sole.dig(:options, :idempotency_key)
    assert_equal "refunded", @order.reload.status
  end

  test "pending provider refund remains reclaimable and later recovers by provider refund id" do
    pending_response = stripe_refund_response(id: "re_test_pending", status: "pending")
    pending_client, = build_stripe_test_client(created_refund: pending_response)

    first = with_stripe_client(pending_client) do
      Commerce::ProcessRefund.call(
        order: @order,
        payment_record: @payment,
        amount_cents: @payment.amount_cents,
        approved_by: @admin
      )
    end

    assert first.failure?
    assert_equal "provider_pending", first.code
    refund = @order.refunds.sole
    assert_equal "approved", refund.status
    assert_equal "re_test_pending", refund.provider_refund_id
    assert_equal "pending", refund.provider_status

    refund.update!(processing_started_at: 10.minutes.ago)
    succeeded_response = stripe_refund_response(id: "re_test_pending", status: "succeeded")
    recovery_client, _, refunds = build_stripe_test_client(
      created_refund: succeeded_response,
      retrieved_refund: succeeded_response
    )

    recovered = with_stripe_client(recovery_client) do
      Commerce::ProcessRefund.call(
        order: @order,
        payment_record: @payment,
        amount_cents: @payment.amount_cents,
        approved_by: @admin,
        existing_refund: refund
      )
    end

    assert recovered.success?, recovered.error
    assert_equal [ "re_test_pending" ], refunds.retrieve_requests
    assert_equal "completed", refund.reload.status
    assert_equal "refunded", @order.reload.status
  end

  private

  def configure_stripe
    Payments::ProviderConfig.find_or_initialize_by(provider: "stripe").tap do |config|
      config.enabled = true
      config.credentials = {
        "secret_key" => "sk_test_real_refund",
        "webhook_secret" => "whsec_real_refund"
      }
      config.save!
      mark_stripe_provider_connection_tested!(config)
    end
  end

  def stripe_refund_response(id:, status:)
    {
      "id" => id,
      "status" => status,
      "livemode" => false,
      "amount" => @payment.amount_cents,
      "currency" => @payment.currency.downcase,
      "payment_intent" => @payment.metadata.fetch("stripe_payment_intent_id"),
      "charge" => "ch_test_refundable",
      "balance_transaction" => "txn_test_refundable"
    }
  end
end
