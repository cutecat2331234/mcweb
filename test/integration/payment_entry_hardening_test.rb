# frozen_string_literal: true

require "test_helper"

class PaymentEntryHardeningTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
  end

  test "enabled and fully configured stripe can start checkout" do
    configure_stripe!(
      enabled: true,
      credentials: {
        "secret_key" => "sk_test_checkout",
        "webhook_secret" => "whsec_checkout"
      }
    )
    order = create_payable_order
    client, = build_stripe_test_client

    with_stripe_client(client) do
      post store_checkout_path, params: {
        order_id: order.public_id,
        checkout: { provider: "stripe" }
      }
    end

    assert_response :redirect
    assert_match %r{\Ahttps://checkout\.stripe\.com/c/pay/}, response.location
    assert_equal "awaiting_payment", order.reload.status
    assert_equal "stripe", order.payment_records.pending.sole.provider
    assert_match(/\Acs_test_/, order.payment_records.pending.sole.provider_payment_id)
  end

  test "repeated checkout reuses one payment record and one Stripe idempotency identity" do
    configure_stripe!(
      enabled: true,
      credentials: {
        "secret_key" => "sk_test_checkout_replay",
        "webhook_secret" => "whsec_checkout_replay"
      }
    )
    order = create_payable_order
    client, sessions = build_stripe_test_client

    with_stripe_client(client) do
      2.times do
        post store_checkout_path, params: {
          order_id: order.public_id,
          checkout: { provider: "stripe" }
        }
        assert_response :redirect
      end
    end

    payment = order.payment_records.where(status: %w[pending processing]).sole
    assert_equal "stripe", payment.provider
    assert_equal 2, sessions.requests.size
    assert_equal 1, sessions.requests.map { |request| request.dig(:options, :idempotency_key) }.uniq.size
    assert_equal "mcweb:checkout:payment:#{payment.id}:v1",
      sessions.requests.first.dig(:options, :idempotency_key)
  end

  test "provider change does not invalidate or replace an active Stripe session" do
    configure_stripe!(
      enabled: true,
      credentials: {
        "secret_key" => "sk_test_checkout_switch",
        "webhook_secret" => "whsec_checkout_switch"
      }
    )
    Payments::ProviderConfig.find_or_initialize_by(provider: "fake").tap do |config|
      config.enabled = true
      config.save!
    end
    order = create_payable_order
    client, = build_stripe_test_client

    with_stripe_client(client) do
      post store_checkout_path, params: {
        order_id: order.public_id,
        checkout: { provider: "stripe" }
      }
    end
    stripe_payment = order.payment_records.pending.sole
    stripe_reference = stripe_payment.provider_payment_id

    post store_checkout_path, params: {
      order_id: order.public_id,
      checkout: { provider: "fake" }
    }

    assert_redirected_to store_order_path(order)
    assert_equal I18n.t("mcweb.services.errors.payment_attempt_already_active"), flash[:alert]
    assert_equal [ stripe_payment.id ], order.payment_records.reload.pluck(:id)
    assert_equal "pending", stripe_payment.reload.status
    assert_equal stripe_reference, stripe_payment.provider_payment_id
  end

  test "disabled provider is rejected before payment state changes" do
    configure_stripe!(
      enabled: false,
      credentials: {
        "secret_key" => "sk_test_disabled",
        "webhook_secret" => "whsec_disabled"
      }
    )
    order = create_payable_order

    post store_checkout_path, params: {
      order_id: order.public_id,
      checkout: { provider: "stripe" }
    }

    assert_redirected_to store_order_path(order)
    assert_equal "pending", order.reload.status
    assert_empty order.payment_records
  end

  test "incomplete provider configuration is rejected before payment state changes" do
    configure_stripe!(
      enabled: true,
      credentials: { "secret_key" => "sk_test_incomplete" }
    )
    order = create_payable_order

    post store_checkout_path, params: {
      order_id: order.public_id,
      checkout: { provider: "stripe" }
    }

    assert_redirected_to store_order_path(order)
    assert_equal "pending", order.reload.status
    assert_empty order.payment_records
  end

  test "production rejects forged fake provider before payment state changes" do
    Payments::ProviderConfig.find_or_initialize_by(provider: "fake").tap do |config|
      config.enabled = true
      config.save!
    end
    order = create_payable_order

    with_rails_environment("production") do
      assert_raises(Payments::Provider::UnknownProviderError) do
        Payments::Provider.for("fake")
      end

      post store_checkout_path, params: {
        order_id: order.public_id,
        checkout: { provider: "fake" }
      }
    end

    assert_redirected_to store_order_path(order)
    assert_equal "pending", order.reload.status
    assert_empty order.payment_records
  end

  test "developer mode production checkout uses virtual fake and rejects stripe" do
    Payments::ProviderConfig.where(provider: "fake").delete_all
    configure_stripe!(
      enabled: true,
      credentials: {
        "secret_key" => "sk_live_developer_checkout",
        "webhook_secret" => "whsec_developer_checkout"
      }
    )
    Payments::ProviderConfig.find_by!(provider: "stripe").update!(mode: "live")
    order = create_payable_order

    with_unrestricted_developer_mode do
      with_rails_environment("production") do
        post store_checkout_path, params: {
          order_id: order.public_id,
          checkout: { provider: "stripe" }
        }

        assert_redirected_to store_order_path(order)
        assert_equal "pending", order.reload.status
        assert_empty order.payment_records

        post store_checkout_path, params: {
          order_id: order.public_id,
          checkout: { provider: "fake" }
        }

        assert_response :redirect
        assert_match %r{/app/payments/fake/fake_}, response.location
        assert_equal "fake", order.payment_records.pending.sole.provider

        follow_redirect!
        assert_response :success
      end
    end
  end

  private

  def configure_stripe!(enabled:, credentials:)
    Payments::ProviderConfig.find_or_initialize_by(provider: "stripe").tap do |config|
      config.enabled = enabled
      config.credentials = credentials
      config.save!
      mark_stripe_provider_connection_tested!(config) if config.configuration_complete?
    end
  end

  def create_payable_order
    suffix = SecureRandom.hex(6)
    Commerce::Order.create!(
      public_id: "ord_payment_hardening_#{suffix}",
      order_number: "PAY-HARD-#{suffix.upcase}",
      user: @user,
      status: "pending",
      subtotal_cents: 1_000,
      total_cents: 1_000,
      discount_cents: 0,
      currency: "CNY"
    )
  end

  def with_rails_environment(name)
    replacement = ActiveSupport::EnvironmentInquirer.new(name)
    singleton = class << Rails; self; end
    original = Rails.env
    singleton.define_method(:env) { replacement }
    yield
  ensure
    singleton.define_method(:env) { original }
  end

  def with_unrestricted_developer_mode
    settings = Mcweb::DeveloperMode.parse(
      config: { developer_mode: { enabled: true, preset: "unrestricted" } },
      environment: {}
    )
    previous_settings = Mcweb::DeveloperMode.instance_variable_get(:@settings)
    Mcweb::DeveloperMode.instance_variable_set(:@settings, settings)
    yield
  ensure
    Mcweb::DeveloperMode.instance_variable_set(:@settings, previous_settings)
  end
end

class PaymentWebhookHardeningTest < ActionDispatch::IntegrationTest
  test "stripe webhook verifies the raw body and enqueues only allowlisted headers" do
    Payments::ProviderConfig.find_or_initialize_by(provider: "stripe").tap do |config|
      config.enabled = false
      config.mode = "test"
      config.credentials = {
        "secret_key" => "sk_test_controller_webhook",
        "webhook_secret" => "whsec_controller_webhook"
      }
      config.save!
      mark_stripe_provider_connection_tested!(config)
      refute config.checkout_ready?
      assert config.reconciliation_ready?
    end
    payload = {
      id: "evt_controller_#{SecureRandom.hex(6)}",
      object: "event",
      type: "customer.updated",
      data: { object: { id: "cus_test" } }
    }.to_json
    signature = stripe_webhook_signature(payload, "whsec_controller_webhook")

    assert_enqueued_jobs 1, only: Payments::ProcessWebhookJob do
      post store_webhook_path(provider: "stripe"),
        params: payload,
        headers: {
          "CONTENT_TYPE" => "application/json",
          "Stripe-Signature" => signature,
          "Authorization" => "Bearer must-not-enter-the-job",
          "Cookie" => "session=must-not-enter-the-job"
        }
    end

    assert_response :ok
    serialized_job = enqueued_jobs.last.fetch(:args).to_s
    assert_includes serialized_job, "webhook_event_id"
    refute_includes serialized_job, signature
    assert_not_includes serialized_job, "must-not-enter-the-job"
  end

  test "unbound Stripe webhook is retryable and is not persisted" do
    Payments::ProviderConfig.find_or_initialize_by(provider: "stripe").tap do |config|
      config.update!(
        enabled: false,
        mode: "test",
        credentials: {
          "secret_key" => "sk_test_unbound_webhook",
          "webhook_secret" => "whsec_unbound_webhook"
        },
        account_fingerprint: nil,
        last_connection_test_status: nil,
        last_connection_test_error_code: nil,
        last_connection_test_mode: nil,
        last_connection_tested_at: nil,
        last_connection_tested_by: nil,
        last_connection_test_credential_revision: nil
      )
    end
    event_id = "evt_unbound_#{SecureRandom.hex(6)}"
    payload = stripe_test_webhook_payload(event_id)
    signature = stripe_webhook_signature(payload, "whsec_unbound_webhook")

    assert_no_difference -> {
      Payments::WebhookEvent.where(
        provider: "stripe",
        event_id: event_id
      ).count
    } do
      assert_no_enqueued_jobs only: Payments::ProcessWebhookJob do
        post_stripe_webhook(payload, signature)
      end
    end

    assert_response :service_unavailable
    assert_equal "60", response.headers["Retry-After"]
  end

  test "stale Stripe credential revision rejects webhook before persistence" do
    config = Payments::ProviderConfig.find_or_initialize_by(provider: "stripe")
    config.update!(
      enabled: false,
      mode: "test",
      credentials: {
        "secret_key" => "sk_test_current_webhook",
        "webhook_secret" => "whsec_current_webhook"
      }
    )
    mark_stripe_provider_connection_tested!(config)
    config.update!(
      credentials: {
        "secret_key" => "sk_test_stale_webhook",
        "webhook_secret" => "whsec_stale_webhook"
      }
    )
    refute config.connection_test_current?

    event_id = "evt_stale_identity_#{SecureRandom.hex(6)}"
    payload = stripe_test_webhook_payload(event_id)
    signature = stripe_webhook_signature(payload, "whsec_stale_webhook")

    assert_no_difference -> {
      Payments::WebhookEvent.where(
        provider: "stripe",
        event_id: event_id
      ).count
    } do
      assert_no_enqueued_jobs only: Payments::ProcessWebhookJob do
        post_stripe_webhook(payload, signature)
      end
    end

    assert_response :service_unavailable
    assert_equal "60", response.headers["Retry-After"]
  end

  test "oversized webhook body is rejected without enqueueing work" do
    payload = { padding: "x" * Commerce::WebhooksController::MAX_WEBHOOK_BODY_BYTES }.to_json
    signature = OpenSSL::HMAC.hexdigest("SHA256", "fake_webhook_secret", payload)

    assert_no_enqueued_jobs only: Payments::ProcessWebhookJob do
      post store_webhook_path(provider: "fake"),
        params: payload,
        headers: {
          "CONTENT_TYPE" => "application/json",
          "X-Webhook-Signature" => signature
        }
    end

    assert_response :content_too_large
  end

  test "unknown stripe event is recorded idempotently without changing payment" do
    Payments::ProviderConfig.find_or_initialize_by(provider: "stripe").tap do |config|
      config.enabled = true
      config.mode = "test"
      config.credentials = {
        "secret_key" => "sk_test_unknown_event",
        "webhook_secret" => "whsec_unknown_event"
      }
      config.save!
      mark_stripe_provider_connection_tested!(config)
    end
    user = create_user
    order = Commerce::Order.create!(
      public_id: "ord_unknown_event_#{SecureRandom.hex(6)}",
      order_number: "UNKNOWN-#{SecureRandom.hex(6).upcase}",
      user: user,
      status: "awaiting_payment",
      subtotal_cents: 1_000,
      total_cents: 1_000,
      discount_cents: 0,
      currency: "CNY"
    )
    payment = Payments::Record.create!(
      order: order,
      provider: "stripe",
      status: "pending",
      amount_cents: 1_000,
      currency: "CNY",
      provider_payment_id: "pi_unknown_#{SecureRandom.hex(6)}"
    )
    payload = {
      id: "evt_unknown_#{SecureRandom.hex(6)}",
      type: "unknown",
      data: {
        object: {
          id: payment.provider_payment_id,
          metadata: { payment_record_id: payment.id.to_s }
        }
      }
    }.to_json
    signature = stripe_webhook_signature(payload, "whsec_unknown_event")
    args = {
      provider: "stripe",
      event_id: JSON.parse(payload).fetch("id"),
      event_type: "unknown",
      payload: payload,
      signature: signature
    }

    first = Payments::WebhookProcessor.call(**args)
    replay = Payments::WebhookProcessor.call(**args)

    assert first.success?
    assert replay.success?
    assert replay.value[:idempotent]
    assert_equal "pending", payment.reload.status
    assert Payments::WebhookEvent.find_by!(
      provider: "stripe",
      event_id: args[:event_id]
    ).processed?
  end

  private

  def stripe_test_webhook_payload(event_id)
    {
      id: event_id,
      object: "event",
      type: "customer.updated",
      data: { object: { id: "cus_test" } }
    }.to_json
  end

  def post_stripe_webhook(payload, signature)
    post store_webhook_path(provider: "stripe"),
      params: payload,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "Stripe-Signature" => signature
      }
  end
end
