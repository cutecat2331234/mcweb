# frozen_string_literal: true

require "test_helper"

class Payments::DeveloperModeIsolationTest < ActiveSupport::TestCase
  setup do
    Payments::ProviderConfig.where(provider: %w[fake stripe]).delete_all
  end

  test "unrestricted mode exposes only a virtual fake provider in production" do
    configure_stripe!
    assert_nil Payments::ProviderConfig.find_by(provider: "fake")

    with_developer_mode do
      with_rails_environment("production") do
        providers = Payments::ProviderConfig.checkout_ready_providers
        fake_config = Payments::ProviderConfig.checkout_config_for("fake")

        assert_equal [ "fake" ], providers.map(&:provider)
        assert_predicate providers.sole, :new_record?
        assert_predicate providers.sole, :checkout_ready?
        assert_predicate fake_config, :new_record?
        assert_predicate fake_config, :checkout_ready?
        assert_nil Payments::ProviderConfig.checkout_config_for("stripe")
        assert Payments::Provider.known?("fake")
        assert_not Payments::Provider.known?("stripe")
        assert_instance_of Payments::FakeProvider, Payments::Provider.for("fake")
        assert_raises(Payments::Provider::UnknownProviderError) do
          Payments::Provider.for("stripe")
        end
      end
    end
  end

  test "disabled mode preserves production provider selection" do
    fake = Payments::ProviderConfig.create!(provider: "fake", enabled: true)
    stripe = configure_stripe!

    with_developer_mode(enabled: false) do
      with_rails_environment("production") do
        assert_equal [ "stripe" ],
          Payments::ProviderConfig.checkout_ready_providers.map(&:provider)
        assert_nil Payments::ProviderConfig.checkout_config_for("fake")
        assert_equal stripe,
          Payments::ProviderConfig.checkout_config_for("stripe")
        assert_not fake.checkout_ready?
        assert Payments::Provider.known?("stripe")
        assert_not Payments::Provider.known?("fake")
      end
    end
  end

  test "payments inherit override keeps configured providers available" do
    Payments::ProviderConfig.create!(provider: "fake", enabled: true)
    configure_stripe!(mode: "test")

    with_developer_mode(integrations: { payments: "inherit" }) do
      assert_equal %w[fake stripe],
        Payments::ProviderConfig.checkout_ready_providers.map(&:provider).sort
      assert Payments::Provider.known?("fake")
      assert Payments::Provider.known?("stripe")
    end
  end

  test "signature bypass accepts an unsigned fake webhook and emits safe telemetry" do
    payload = { payment_id: "fake_dev_payment" }.to_json
    events = []
    subscriber = ActiveSupport::Notifications.subscribe(
      "payments.webhook.signature_bypassed"
    ) do |event|
      events << event.payload
    end

    result = with_developer_mode do
      with_rails_environment("production") do
        Payments::ReceiveWebhook.call(
          provider: "fake",
          event_id: "evt_dev_unsigned",
          event_type: "payment.succeeded",
          payload: payload,
          signature: ""
        )
      end
    end

    assert_predicate result, :success?
    assert_equal true, result.value.fetch(:signature_bypassed)
    assert_equal "evt_dev_unsigned", result.value.fetch(:event).event_id
    assert result.value.fetch(:event).verified_at.present?
    assert_equal 1, events.size
    assert_equal(
      {
        provider: "fake",
        event_id: "evt_dev_unsigned",
        event_type: "payment.succeeded"
      },
      events.sole
    )
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  test "signature bypass does not admit stripe while fake isolation is active" do
    configure_stripe!
    payload = {
      id: "evt_dev_stripe",
      type: "checkout.session.completed"
    }.to_json

    result = with_developer_mode do
      Payments::ReceiveWebhook.call(
        provider: "stripe",
        event_id: "evt_dev_stripe",
        event_type: "checkout.session.completed",
        payload: payload,
        signature: ""
      )
    end

    assert_predicate result, :failure?
    assert_equal "unknown_provider", result.code
    assert_not Payments::WebhookEvent.exists?(
      provider: "stripe",
      event_id: "evt_dev_stripe"
    )
  end

  test "disabled signature bypass retains signature verification" do
    payload = { payment_id: "fake_signed_payment" }.to_json

    unsigned = with_developer_mode(enabled: false) do
      Payments::ReceiveWebhook.call(
        provider: "fake",
        event_id: "evt_dev_unsigned_rejected",
        event_type: "payment.succeeded",
        payload: payload,
        signature: ""
      )
    end
    signed = with_developer_mode(enabled: false) do
      Payments::ReceiveWebhook.call(
        provider: "fake",
        event_id: "evt_dev_signed",
        event_type: "payment.succeeded",
        payload: payload,
        signature: OpenSSL::HMAC.hexdigest(
          "SHA256",
          "fake_webhook_secret",
          payload
        )
      )
    end

    assert_predicate unsigned, :failure?
    assert_equal "invalid_signature", unsigned.code
    assert_not Payments::WebhookEvent.exists?(
      provider: "fake",
      event_id: "evt_dev_unsigned_rejected"
    )
    assert_predicate signed, :success?
    assert_equal false, signed.value.fetch(:signature_bypassed)
  end

  test "signature inherit override retains verification while mode stays enabled" do
    payload = { payment_id: "fake_inherit_payment" }.to_json

    result = with_developer_mode(
      security: { inbound_webhook_signatures: "inherit" }
    ) do
      Payments::ReceiveWebhook.call(
        provider: "fake",
        event_id: "evt_dev_signature_inherit",
        event_type: "payment.succeeded",
        payload: payload,
        signature: ""
      )
    end

    assert_predicate result, :failure?
    assert_equal "invalid_signature", result.code
  end

  private

  def configure_stripe!(mode: "live")
    config = Payments::ProviderConfig.create!(
      provider: "stripe",
      enabled: true,
      mode: mode,
      credentials: {
        "secret_key" => "sk_#{mode}_developer_mode_isolation",
        "webhook_secret" => "whsec_developer_mode_isolation"
      }
    )
    mark_stripe_provider_connection_tested!(config)
  end

  def with_developer_mode(
    enabled: true,
    security: {},
    integrations: {},
    &block
  )
    settings = Mcweb::DeveloperMode.parse(
      config: {
        developer_mode: {
          enabled: enabled,
          preset: "unrestricted",
          security: security,
          integrations: integrations
        }
      },
      environment: {}
    )
    previous_settings = Mcweb::DeveloperMode.instance_variable_get(:@settings)
    Mcweb::DeveloperMode.instance_variable_set(:@settings, settings)
    block.call
  ensure
    Mcweb::DeveloperMode.instance_variable_set(:@settings, previous_settings)
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
end
