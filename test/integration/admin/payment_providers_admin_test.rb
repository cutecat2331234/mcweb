# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  module Store
    class PaymentProvidersAdminTest < ActionDispatch::IntegrationTest
      setup do
        @admin = create_user
        grant_permission(@admin, "admin.access")
        grant_permission(@admin, Payments::UpdateProviderConfiguration::PERMISSION)
        sign_in_as(@admin)

        @config = Payments::ProviderConfig.find_or_initialize_by(provider: "stripe")
        @config.update!(
          enabled: false,
          mode: "test",
          credentials: {
            "secret_key" => "sk_test_payment_admin_private",
            "webhook_secret" => "whsec_payment_admin_private"
          }
        )
      end

      test "configuration page exposes only safe Stripe state" do
        get admin_store_payment_providers_path

        assert_response :success
        props = inertia.props.deep_symbolize_keys
        provider = props.fetch(:providerConfig)
        assert_equal "stripe", provider[:provider]
        assert provider.dig(:credentials, :secret_key, :configured)
        assert provider.dig(:credentials, :webhook_secret, :configured)
        refute provider.dig(:account_binding, :bound)
        refute provider.dig(:account_binding, :connection_current)
        refute provider.dig(:connection_test, :allowed)
        assert_nil provider.dig(:connection_test, :token)
        assert_equal "/app/store/webhooks/stripe",
          URI.parse(provider.dig(:webhook, :endpoint)).path
        assert_sensitive_values_absent(props)
        refute_includes props.to_json, "account_fingerprint"
        assert_equal "no-store", response.headers["Cache-Control"]
      end

      test "blank updates preserve secrets and replacement responses never echo them" do
        patch admin_store_payment_providers_path, params: {
          provider_config: {
            enabled: "0",
            mode: "test",
            secret_key: "",
            webhook_secret: ""
          }
        }

        assert_redirected_to admin_store_payment_providers_path
        assert_equal "sk_test_payment_admin_private",
          @config.reload.credentials_hash.stringify_keys["secret_key"]
        refute_includes response.body, "sk_test_payment_admin_private"

        patch admin_store_payment_providers_path, params: {
          provider_config: {
            enabled: "0",
            mode: "test",
            secret_key: "sk_test_payment_admin_replacement_private",
            webhook_secret: ""
          }
        }

        assert_redirected_to admin_store_payment_providers_path
        refute_includes response.body, "sk_test_payment_admin_replacement_private"
        get admin_store_payment_providers_path
        assert_sensitive_values_absent(inertia.props.deep_symbolize_keys)
      end

      test "dedicated connection permission issues a version-bound token and the endpoint uses a stubbed probe" do
        grant_permission(@admin, Payments::TestProviderConnection::PERMISSION)
        get admin_store_payment_providers_path
        props = inertia.props.deep_symbolize_keys
        token = props.dig(:providerConfig, :connection_test, :token)

        assert token.present?
        observed_probe_arguments = nil
        probe = lambda do |secret_key:, expected_mode:|
          observed_probe_arguments = {
            secret_key: secret_key,
            expected_mode: expected_mode
          }
          ServiceResult.success(
            mode: expected_mode,
            account_fingerprint:
              Payments::StripeConnectionProbe.account_fingerprint(
                "acct_1234567890ABCDEF"
              )
          )
        end

        with_stripe_connection_probe(probe) do
          post admin_store_payment_provider_connection_test_path, params: {
            token: token,
            confirmation: "stripe"
          }
        end

        assert_equal(
          {
            secret_key: "sk_test_payment_admin_private",
            expected_mode: "test"
          },
          observed_probe_arguments
        )
        assert_redirected_to admin_store_payment_providers_path
        assert_equal "success", @config.reload.last_connection_test_status
        assert @config.connection_test_current?
        assert @config.stripe_account_bound?
        refute_includes response.body, "sk_test_payment_admin_private"
      end

      test "configuration permission does not grant connection testing" do
        get admin_store_payment_providers_path
        token = Payments::ProviderConnectionTestToken.issue(@config)

        assert_no_difference -> {
          AuditLog.where(action: "admin.payment_provider_connection_tested").count
        } do
          post admin_store_payment_provider_connection_test_path, params: {
            token: token,
            confirmation: "stripe"
          }
        end

        assert_redirected_to root_path
        assert_nil @config.reload.last_connection_test_status
      end

      test "admin access without the dedicated configuration permission cannot read or update" do
        delete identity_session_path
        limited = create_user
        grant_permission(limited, "admin.access")
        sign_in_as(limited)

        get admin_store_payment_providers_path
        assert_redirected_to admin_root_path

        assert_no_changes -> { @config.reload.encrypted_credentials } do
          patch admin_store_payment_providers_path, params: {
            provider_config: {
              enabled: "1",
              mode: "live",
              secret_key: "sk_live_forbidden_private",
              webhook_secret: "whsec_forbidden_private"
            }
          }
        end
        assert_redirected_to admin_root_path
      end

      private

      def with_stripe_connection_probe(replacement)
        singleton = Payments::StripeConnectionProbe.singleton_class
        had_own_call = singleton.instance_methods(false).include?(:call)
        original_call = singleton.instance_method(:call) if had_own_call
        singleton.define_method(:call, &replacement)
        yield
      ensure
        if had_own_call
          singleton.define_method(:call, original_call)
        else
          singleton.remove_method(:call)
        end
      end

      def assert_sensitive_values_absent(value)
        rendered = value.to_json
        refute_includes rendered, "sk_test_payment_admin_private"
        refute_includes rendered, "whsec_payment_admin_private"
        refute_includes rendered, "sk_test_payment_admin_replacement_private"
        refute_includes rendered, @config.reload.encrypted_credentials
        refute_includes rendered, @config.account_fingerprint if @config.account_fingerprint
      end
    end
  end
end
