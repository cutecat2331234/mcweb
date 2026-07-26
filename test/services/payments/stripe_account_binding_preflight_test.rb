# frozen_string_literal: true

require "test_helper"

module Payments
  class StripeAccountBindingPreflightTest < ActiveSupport::TestCase
    setup do
      @config = Payments::ProviderConfig.find_or_initialize_by(
        provider: "stripe"
      )
      @config.update!(
        enabled: false,
        mode: "test",
        credentials: {
          "secret_key" => "sk_test_binding_preflight",
          "webhook_secret" => "whsec_binding_preflight"
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

    test "fresh installation passes without inventing an account binding" do
      result = Payments::StripeAccountBindingPreflight.call

      assert result.success?, result.error
      refute result.value[:account_bound]
      refute result.value[:financial_history_present]
      assert_nil @config.reload.account_fingerprint
    end

    test "fresh unbound installation must disable Stripe before release" do
      @config.update!(enabled: true)

      result = Payments::StripeAccountBindingPreflight.call

      assert result.failure?
      assert_equal "stripe_account_binding_disable_required", result.code
      refute result.value[:account_bound]
      refute result.value[:financial_history_present]
      assert result.value[:provider_enabled]
      assert @config.reload.enabled?
      assert_nil @config.account_fingerprint
    end

    test "unbound financial history blocks release without mutating data" do
      @config.update!(enabled: true)
      payment = create_stripe_payment_history!

      assert_no_changes -> { @config.reload.attributes } do
        result = Payments::StripeAccountBindingPreflight.call

        assert result.failure?
        assert_equal(
          Payments::StripeAccountBindingPreflight::RELEASE_BLOCKED_CODE,
          result.code
        )
        refute result.value[:account_bound]
        assert result.value[:financial_history_present]
        assert result.value[:provider_enabled]
      end
      assert payment.persisted?
      assert_nil @config.reload.account_fingerprint
    end

    test "verified binding permits a deployment that already has history" do
      mark_stripe_provider_connection_tested!(@config)
      create_stripe_payment_history!

      result = Payments::StripeAccountBindingPreflight.call

      assert result.success?, result.error
      assert result.value[:account_bound]
      assert result.value[:financial_history_present]
    end

    test "empty skipped reconciliation run is not financial history" do
      start_at = Time.utc(2026, 6, 1)
      Payments::ReconciliationRun.create!(
        provider: "stripe",
        mode: "test",
        window_start: start_at,
        window_end: start_at + 1.day,
        status: "skipped",
        phase: "completed",
        failure_code: "provider_not_configured"
      )

      result = Payments::StripeAccountBindingPreflight.call

      assert result.success?, result.error
      refute result.value[:financial_history_present]
    end

    private

    def create_stripe_payment_history!
      suffix = SecureRandom.hex(6)
      order = Commerce::Order.create!(
        public_id: "ord_binding_preflight_#{suffix}",
        order_number: "BINDING-PREFLIGHT-#{suffix.upcase}",
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
        provider_payment_id: "pi_binding_preflight_#{suffix}"
      )
    end
  end
end
