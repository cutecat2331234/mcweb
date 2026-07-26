# frozen_string_literal: true

require "test_helper"

module Payments
  class StripeReconciliationClientTest < ActiveSupport::TestCase
    test "applies bounded defaults to a per-client Stripe configuration" do
      global_before = global_network_configuration

      client = StripeReconciliationClient.new.build(
        secret_key: "sk_test_reconciliation_timeout"
      )
      configuration = client_configuration(client)

      assert_equal 5, configuration.open_timeout
      assert_equal 15, configuration.read_timeout
      assert_equal 5, configuration.write_timeout
      assert_equal 1, configuration.max_network_retries
      assert_equal 1, configuration.initial_network_retry_delay
      assert_equal 1, configuration.max_network_retry_delay
      assert_equal 51,
        StripeReconciliationClient.new.network_budget
          .configured_timeout_budget_seconds
      assert_equal global_before, global_network_configuration
      refute_same Stripe.config, configuration
    end

    test "clamps configuration to a sixty second maximum without cross-client pollution" do
      first = StripeReconciliationClient.new(
        environment: {
          "MCWEB_STRIPE_RECONCILIATION_OPEN_TIMEOUT_SECONDS" => "500",
          "MCWEB_STRIPE_RECONCILIATION_READ_TIMEOUT_SECONDS" => "500",
          "MCWEB_STRIPE_RECONCILIATION_WRITE_TIMEOUT_SECONDS" => "500",
          "MCWEB_STRIPE_RECONCILIATION_MAX_NETWORK_RETRIES" => "500",
          "MCWEB_STRIPE_RECONCILIATION_NETWORK_RETRY_DELAY_SECONDS" => "500"
        }
      )
      second = StripeReconciliationClient.new(
        environment: {
          "MCWEB_STRIPE_RECONCILIATION_OPEN_TIMEOUT_SECONDS" => "2",
          "MCWEB_STRIPE_RECONCILIATION_READ_TIMEOUT_SECONDS" => "7",
          "MCWEB_STRIPE_RECONCILIATION_WRITE_TIMEOUT_SECONDS" => "3",
          "MCWEB_STRIPE_RECONCILIATION_MAX_NETWORK_RETRIES" => "0",
          "MCWEB_STRIPE_RECONCILIATION_NETWORK_RETRY_DELAY_SECONDS" => "0"
        }
      )

      first_client = first.build(secret_key: "sk_test_first_timeout")
      second_client = second.build(secret_key: "sk_test_second_timeout")
      first_configuration = client_configuration(first_client)
      second_configuration = client_configuration(second_client)

      assert_equal [ 5, 19, 5, 1, 2, 2 ],
        network_configuration(first_configuration)
      assert_equal 60, first.network_budget.configured_timeout_budget_seconds
      assert_equal [ 2, 7, 3, 0, 0, 0 ],
        network_configuration(second_configuration)
      assert_equal 12, second.network_budget.configured_timeout_budget_seconds
      refute_same first_configuration, second_configuration
    end

    test "invalid values use defaults and values below the safe floor are raised" do
      builder = StripeReconciliationClient.new(
        environment: {
          "MCWEB_STRIPE_RECONCILIATION_OPEN_TIMEOUT_SECONDS" => "invalid",
          "MCWEB_STRIPE_RECONCILIATION_READ_TIMEOUT_SECONDS" => "-4",
          "MCWEB_STRIPE_RECONCILIATION_WRITE_TIMEOUT_SECONDS" => "0",
          "MCWEB_STRIPE_RECONCILIATION_MAX_NETWORK_RETRIES" => "-1",
          "MCWEB_STRIPE_RECONCILIATION_NETWORK_RETRY_DELAY_SECONDS" =>
            "invalid"
        }
      )

      assert_equal [ 5, 1, 1, 0, 1, 1 ],
        network_configuration(
          client_configuration(
            builder.build(secret_key: "sk_test_invalid_timeout")
          )
        )
    end

    test "fails closed when the current Stripe client contract is unavailable" do
      builder = StripeReconciliationClient.new(
        environment: {},
        client_factory: ->(_api_key) { Object.new }
      )

      error = assert_raises(
        StripeReconciliationClient::UnsupportedClientConfiguration
      ) do
        builder.build(secret_key: "sk_test_unsupported_timeout")
      end

      assert_includes error.message, "isolated request configuration"
    end

    private

    def client_configuration(client)
      client.instance_variable_get(:@requestor).config
    end

    def global_network_configuration
      network_configuration(Stripe.config)
    end

    def network_configuration(configuration)
      [
        configuration.open_timeout,
        configuration.read_timeout,
        configuration.write_timeout,
        configuration.max_network_retries,
        configuration.initial_network_retry_delay,
        configuration.max_network_retry_delay
      ]
    end
  end
end
