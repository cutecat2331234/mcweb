# frozen_string_literal: true

require "test_helper"

class Payments::ProviderConfigurationManagementTest < ActiveSupport::TestCase
  setup do
    @actor = create_user
    grant_permission(@actor, Payments::UpdateProviderConfiguration::PERMISSION)
    grant_permission(@actor, Payments::TestProviderConnection::PERMISSION)
    @config = Payments::ProviderConfig.find_or_initialize_by(provider: "stripe")
    @config.update!(
      enabled: false,
      mode: "test",
      credentials: {
        "secret_key" => "sk_test_payment_configuration_private",
        "webhook_secret" => "whsec_payment_configuration_private"
      }
    )
  end

  test "credentials stay encrypted at rest and serialization exposes presence only" do
    encrypted = @config.reload.encrypted_credentials
    refute_includes encrypted, "sk_test_payment_configuration_private"
    refute_includes encrypted, "whsec_payment_configuration_private"

    webhook = Payments::StripeWebhookConfigurationCheck.call(
      config: @config,
      public_url: "https://payments.example.com"
    )
    serialized = Payments::ProviderConfigurationSerializer.call(
      config: @config,
      webhook_check: webhook.value,
      connection_test_token: Payments::ProviderConnectionTestToken.issue(@config),
      connection_test_allowed: true
    )
    rendered = serialized.to_json

    assert serialized.dig(:credentials, :secret_key, :configured)
    assert serialized.dig(:credentials, :webhook_secret, :configured)
    refute serialized.dig(:account_binding, :bound)
    refute serialized.dig(:account_binding, :connection_current)
    refute_includes rendered, "sk_test_payment_configuration_private"
    refute_includes rendered, "whsec_payment_configuration_private"
    refute_includes rendered, @config.encrypted_credentials
    refute_includes rendered, "account_fingerprint"
  end

  test "blank credential inputs retain encrypted values without invalidating a prior test" do
    tested_at = 1.minute.ago
    mark_stripe_provider_connection_tested!(
      @config,
      tested_at: tested_at,
      actor: @actor
    )
    encrypted_before = @config.encrypted_credentials

    result = Payments::UpdateProviderConfiguration.call(
      actor: @actor,
      attributes: {
        mode: "test",
        enabled: false,
        secret_key: "",
        webhook_secret: ""
      }
    )

    assert result.success?, result.error
    @config.reload
    assert_equal encrypted_before, @config.encrypted_credentials
    assert_equal "sk_test_payment_configuration_private",
      @config.credentials_hash.stringify_keys["secret_key"]
    assert_equal "success", @config.last_connection_test_status
  end

  test "replacement is mode checked and resets stale connection-test state" do
    mark_stripe_provider_connection_tested!(
      @config,
      tested_at: 1.minute.ago,
      actor: @actor
    )

    mismatch = Payments::UpdateProviderConfiguration.call(
      actor: @actor,
      attributes: {
        mode: "live",
        enabled: false,
        secret_key: "",
        webhook_secret: ""
      }
    )

    assert mismatch.failure?
    assert_equal "mode_mismatch", mismatch.code
    assert_equal "test", @config.reload.mode

    replacement = Payments::UpdateProviderConfiguration.call(
      actor: @actor,
      attributes: {
        mode: "test",
        enabled: false,
        secret_key: "sk_test_payment_configuration_replaced",
        webhook_secret: ""
      }
    )

    assert replacement.success?, replacement.error
    @config.reload
    assert_equal "sk_test_payment_configuration_replaced",
      @config.credentials_hash.stringify_keys["secret_key"]
    assert_nil @config.last_connection_test_status
    assert_nil @config.last_connection_tested_at
    assert_nil @config.last_connection_test_credential_revision
    assert @config.stripe_account_bound?
  end

  test "explicit removal is supported but incomplete credentials cannot be enabled" do
    blocked = Payments::UpdateProviderConfiguration.call(
      actor: @actor,
      attributes: {
        mode: "test",
        enabled: true,
        clear_webhook_secret: true
      }
    )

    assert blocked.failure?
    assert_equal "credentials_incomplete", blocked.code
    assert @config.reload.credential_configured?("webhook_secret")

    removed = Payments::UpdateProviderConfiguration.call(
      actor: @actor,
      attributes: {
        mode: "test",
        enabled: false,
        clear_webhook_secret: true
      }
    )

    assert removed.success?, removed.error
    refute @config.reload.credential_configured?("webhook_secret")
    refute @config.checkout_ready?
  end

  test "configuration audit contains only safe state and changed field names" do
    result = Payments::UpdateProviderConfiguration.call(
      actor: @actor,
      attributes: {
        mode: "test",
        enabled: false,
        secret_key: "sk_test_payment_configuration_audit_private",
        webhook_secret: ""
      },
      ip_address: "127.0.0.1",
      user_agent: "Configuration test"
    )

    assert result.success?, result.error
    audit = AuditLog.where(
      actor: @actor,
      action: "admin.payment_provider_configuration_updated"
    ).order(:id).last
    assert audit
    serialized_audit = audit.attributes.to_json
    refute_includes serialized_audit, "sk_test_payment_configuration_audit_private"
    refute_includes serialized_audit, "whsec_payment_configuration_private"
    assert_equal "stripe", audit.metadata["provider"]
  end

  test "webhook check validates the route endpoint secret and mode without an external request" do
    ready = Payments::StripeWebhookConfigurationCheck.call(
      config: @config,
      public_url: "https://payments.example.com"
    )

    assert ready.success?
    assert ready.value[:ready]
    assert_equal "https://payments.example.com/app/store/webhooks/stripe",
      ready.value[:endpoint]
    assert_includes ready.value[:required_events], "checkout.session.completed"
    assert ready.value[:checks].all? { |check| check[:ok] }

    unsafe_webhook_value = "plain_webhook_value_must_not_leak"
    @config.update!(
      credentials: @config.credentials_hash.merge(
        "webhook_secret" => unsafe_webhook_value
      )
    )
    invalid = Payments::StripeWebhookConfigurationCheck.call(
      config: @config,
      public_url: "not a URL"
    )

    refute invalid.value[:ready]
    assert_includes invalid.value[:checks].filter_map { |check| check[:code] unless check[:ok] },
      "public_url_invalid"
    assert_includes invalid.value[:checks].filter_map { |check| check[:code] unless check[:ok] },
      "webhook_secret_invalid"
    refute_includes invalid.value.to_json, unsafe_webhook_value
  end

  test "connection test requires permission confirmation and a current token" do
    limited_actor = create_user
    probe = Object.new
    probe.define_singleton_method(:call) do |**|
      raise "probe must not run"
    end

    forbidden = Payments::TestProviderConnection.call(
      actor: limited_actor,
      token: Payments::ProviderConnectionTestToken.issue(@config),
      confirmation: "stripe",
      probe: probe
    )
    assert forbidden.failure?
    assert_equal "forbidden", forbidden.code

    wrong_confirmation = Payments::TestProviderConnection.call(
      actor: @actor,
      token: Payments::ProviderConnectionTestToken.issue(@config),
      confirmation: "Stripe",
      probe: probe
    )
    assert wrong_confirmation.failure?
    assert_equal "invalid_confirmation", wrong_confirmation.code

    stale_token = Payments::ProviderConnectionTestToken.issue(@config)
    @config.touch
    stale = Payments::TestProviderConnection.call(
      actor: @actor,
      token: stale_token,
      confirmation: "stripe",
      probe: probe
    )
    assert stale.failure?
    assert_equal "invalid_test_token", stale.code
  end

  test "developer fake payments block connection tests before loading Stripe configuration" do
    probe = Object.new
    probe.define_singleton_method(:call) do |**|
      raise "probe must not run in Developer Mode fake payments"
    end

    result = nil
    Mcweb::DeveloperMode.stub(:enabled?, true) do
      Mcweb::DeveloperMode.stub(:integration, :fake) do
        Payments::ProviderConfig.stub(:find_by, ->(**) {
          raise "Stripe configuration must not be loaded"
        }) do
          result = Payments::TestProviderConnection.call(
            actor: @actor,
            token: "must-not-be-read",
            confirmation: "stripe",
            probe: probe
          )
        end
      end
    end

    assert result.failure?
    assert_equal "developer_mode_fake_only", result.code
    assert_includes result.error, "开发模式"
    assert_includes result.error, "Stripe"
  end

  test "successful connection test records safe status and a credential-free audit" do
    probe = successful_probe(
      account_id: "acct_1234567890ABCDEF",
      expected_secret_key: "sk_test_payment_configuration_private"
    )

    result = Payments::TestProviderConnection.call(
      actor: @actor,
      token: Payments::ProviderConnectionTestToken.issue(@config),
      confirmation: "stripe",
      probe: probe
    )

    assert result.success?, result.error
    @config.reload
    assert_equal "success", @config.last_connection_test_status
    assert_equal "test", @config.last_connection_test_mode
    assert_equal @actor, @config.last_connection_tested_by
    assert @config.stripe_account_bound?
    assert @config.connection_test_current?
    assert_equal @config.credential_revision,
      @config.last_connection_test_credential_revision

    audit = AuditLog.where(
      actor: @actor,
      action: "admin.payment_provider_connection_tested"
    ).order(:id).last
    assert audit
    rendered = audit.attributes.to_json
    refute_includes rendered, "sk_test_payment_configuration_private"
    refute_includes rendered, "whsec_payment_configuration_private"
    refute_includes rendered, "acct_1234567890ABCDEF"
    refute_includes rendered, @config.account_fingerprint
    assert_equal "success", audit.metadata["status"]
    assert_equal "bound", audit.metadata["account_binding"]
  end

  test "first binding fails closed when Stripe financial history already exists" do
    create_stripe_payment_history!
    account_id = "acct_ABCDEF1234567890"

    result = run_connection_test(
      probe: successful_probe(account_id: account_id)
    )

    assert result.failure?
    assert_equal "account_history_unbound", result.code
    @config.reload
    assert_nil @config.account_fingerprint
    assert_equal "failed", @config.last_connection_test_status
    assert_equal "account_history_unbound",
      @config.last_connection_test_error_code
    refute @config.connection_test_current?
    refute_includes result.error, account_id

    audit = AuditLog.where(
      actor: @actor,
      action: "admin.payment_provider_connection_tested"
    ).order(:id).last
    assert_equal "unbound", audit.metadata["account_binding"]
    refute_includes audit.attributes.to_json, account_id
  end

  test "empty skipped reconciliation does not block a safe first binding" do
    start_at = Time.utc(2026, 7, 1)
    Payments::ReconciliationRun.create!(
      provider: "stripe",
      mode: "test",
      window_start: start_at,
      window_end: start_at + 1.day,
      status: "skipped",
      phase: "completed",
      failure_code: "provider_not_configured"
    )

    result = run_connection_test(
      probe: successful_probe(account_id: "acct_1111222233334444")
    )

    assert result.success?, result.error
    assert @config.reload.stripe_account_bound?
  end

  test "reconciliation observations count as history even without a local payment" do
    start_at = Time.utc(2026, 7, 2)
    run = Payments::ReconciliationRun.create!(
      provider: "stripe",
      mode: "test",
      window_start: start_at,
      window_end: start_at + 1.day,
      status: "completed",
      phase: "completed"
    )
    run.observations.create!(
      subject_type: "payment",
      reference_digest: Digest::SHA256.hexdigest("provider-only-payment")
    )

    result = run_connection_test(
      probe: successful_probe(account_id: "acct_5555666677778888")
    )

    assert result.failure?
    assert_equal "account_history_unbound", result.code
    assert_nil @config.reload.account_fingerprint
  end

  test "same-account key rotation is allowed while another Stripe account is blocked" do
    first_account = "acct_AAAA1111BBBB2222"
    first = run_connection_test(
      probe: successful_probe(account_id: first_account)
    )
    assert first.success?, first.error
    original_fingerprint = @config.reload.account_fingerprint

    enabled = Payments::UpdateProviderConfiguration.call(
      actor: @actor,
      attributes: {
        mode: "test",
        enabled: true,
        secret_key: "",
        webhook_secret: ""
      }
    )
    assert enabled.success?, enabled.error
    assert @config.reload.connection_test_current?
    assert @config.checkout_ready?

    create_stripe_payment_history!
    replaced = Payments::UpdateProviderConfiguration.call(
      actor: @actor,
      attributes: {
        mode: "test",
        enabled: true,
        secret_key: "sk_test_payment_configuration_rotated",
        webhook_secret: ""
      }
    )
    assert replaced.success?, replaced.error
    @config.reload
    assert_equal original_fingerprint, @config.account_fingerprint
    refute @config.connection_test_current?
    refute @config.checkout_ready?

    same_account = run_connection_test(
      probe: successful_probe(
        account_id: first_account,
        expected_secret_key: "sk_test_payment_configuration_rotated"
      )
    )
    assert same_account.success?, same_account.error
    assert @config.reload.connection_test_current?
    assert @config.checkout_ready?

    second_replacement = Payments::UpdateProviderConfiguration.call(
      actor: @actor,
      attributes: {
        mode: "test",
        enabled: true,
        secret_key: "sk_test_payment_configuration_other_account",
        webhook_secret: ""
      }
    )
    assert second_replacement.success?, second_replacement.error

    other_account_id = "acct_CCCC3333DDDD4444"
    mismatch = run_connection_test(
      probe: successful_probe(
        account_id: other_account_id,
        expected_secret_key: "sk_test_payment_configuration_other_account"
      )
    )
    assert mismatch.failure?
    assert_equal "account_mismatch", mismatch.code
    @config.reload
    assert_equal original_fingerprint, @config.account_fingerprint
    refute @config.connection_test_current?
    refute @config.checkout_ready?
    refute_includes mismatch.error, other_account_id
  end

  test "connection test times out and stores only a safe error code" do
    slow_probe = Object.new
    slow_probe.define_singleton_method(:call) do |**|
      sleep 0.05
      ServiceResult.success(mode: "test")
    end

    result = Payments::TestProviderConnection.call(
      actor: @actor,
      token: Payments::ProviderConnectionTestToken.issue(@config),
      confirmation: "stripe",
      probe: slow_probe,
      timeout_seconds: 0.001
    )

    assert result.failure?
    assert_equal "timeout", result.code
    @config.reload
    assert_equal "failed", @config.last_connection_test_status
    assert_equal "timeout", @config.last_connection_test_error_code
  end

  test "configuration changes during the probe cannot record a stale success" do
    fingerprint = Payments::StripeConnectionProbe.account_fingerprint(
      "acct_777788889999AAAA"
    )
    probe = lambda do |**|
      @config.update!(
        credentials: @config.credentials_hash.merge(
          "secret_key" => "sk_test_changed_during_probe"
        )
      )
      ServiceResult.success(
        mode: "test",
        account_fingerprint: fingerprint
      )
    end

    result = Payments::TestProviderConnection.call(
      actor: @actor,
      token: Payments::ProviderConnectionTestToken.issue(@config),
      confirmation: "stripe",
      probe: probe
    )

    assert result.failure?
    assert_equal "configuration_changed", result.code
    @config.reload
    assert_nil @config.last_connection_test_status
    assert_nil @config.account_fingerprint
  end

  test "Stripe probe uses the official client and returns no account balance data" do
    balance_service = Object.new
    balance_service.define_singleton_method(:retrieve) do
      { "livemode" => false, "available" => [ { "amount" => 9_999_999 } ] }
    end
    account_id = "acct_99990000AAAABBBB"
    accounts_service = Object.new
    accounts_service.define_singleton_method(:retrieve_current) do
      { "id" => account_id, "email" => "private-account@example.com" }
    end
    client = OpenStruct.new(
      v1: OpenStruct.new(
        balance: balance_service,
        accounts: accounts_service
      )
    )

    result = with_stripe_client(client) do
      Payments::StripeConnectionProbe.call(
        secret_key: "sk_test_payment_configuration_private",
        expected_mode: "test"
      )
    end

    assert result.success?, result.error
    assert_equal "test", result.value[:mode]
    assert_match Payments::ProviderConfig::SHA256_HEX_PATTERN,
      result.value[:account_fingerprint]
    refute_includes result.value.to_json, "9999999"
    refute_includes result.value.to_json, account_id
    refute_includes result.value.to_json, "private-account@example.com"
  end

  test "Stripe probe rejects an invalid current-account response" do
    balance_service = Object.new
    balance_service.define_singleton_method(:retrieve) do
      { "livemode" => false }
    end
    accounts_service = Object.new
    accounts_service.define_singleton_method(:retrieve_current) do
      { "id" => "acct_short" }
    end
    client = OpenStruct.new(
      v1: OpenStruct.new(
        balance: balance_service,
        accounts: accounts_service
      )
    )

    result = with_stripe_client(client) do
      Payments::StripeConnectionProbe.call(
        secret_key: "sk_test_payment_configuration_private",
        expected_mode: "test"
      )
    end

    assert result.failure?
    assert_equal "invalid_response", result.code
  end

  test "Stripe probe maps restricted-key permission errors without details" do
    private_provider_message = "acct_private must never leak"
    balance_service = Object.new
    balance_service.define_singleton_method(:retrieve) do
      raise Stripe::PermissionError, private_provider_message
    end
    client = OpenStruct.new(v1: OpenStruct.new(balance: balance_service))

    result = with_stripe_client(client) do
      Payments::StripeConnectionProbe.call(
        secret_key: "rk_test_payment_configuration_private",
        expected_mode: "test"
      )
    end

    assert result.failure?
    assert_equal "permission_denied", result.code
    refute_includes result.error, private_provider_message
    refute_includes result.error, "acct_private"
  end

  private

  def successful_probe(
    account_id:,
    expected_secret_key: "sk_test_payment_configuration_private"
  )
    fingerprint =
      Payments::StripeConnectionProbe.account_fingerprint(account_id)
    lambda do |secret_key:, expected_mode:|
      raise "unexpected key" unless secret_key == expected_secret_key

      ServiceResult.success(
        mode: expected_mode,
        account_fingerprint: fingerprint
      )
    end
  end

  def run_connection_test(probe:)
    Payments::TestProviderConnection.call(
      actor: @actor,
      token: Payments::ProviderConnectionTestToken.issue(@config.reload),
      confirmation: "stripe",
      probe: probe
    )
  end

  def create_stripe_payment_history!
    suffix = SecureRandom.hex(6)
    order = Commerce::Order.create!(
      public_id: "ord_account_binding_#{suffix}",
      order_number: "ACCOUNT-BINDING-#{suffix.upcase}",
      user: create_user,
      status: "awaiting_payment",
      subtotal_cents: 1_000,
      discount_cents: 0,
      total_cents: 1_000,
      currency: "CNY"
    )
    Payments::Record.create!(
      order: order,
      provider: "stripe",
      provider_mode: "test",
      status: "pending",
      amount_cents: 1_000,
      currency: "CNY",
      provider_payment_id: "pi_account_binding_#{suffix}"
    )
  end
end
