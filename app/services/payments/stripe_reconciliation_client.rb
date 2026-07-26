# frozen_string_literal: true

module Payments
  class StripeReconciliationClient
    class UnsupportedClientConfiguration < StandardError; end

    Budget = Data.define(
      :open_timeout,
      :read_timeout,
      :write_timeout,
      :max_network_retries,
      :retry_delay
    ) do
      def configured_timeout_budget_seconds
        (open_timeout + read_timeout + write_timeout) *
          (max_network_retries + 1) +
          (retry_delay * max_network_retries)
      end
    end

    ENVIRONMENT_KEYS = {
      open_timeout: "MCWEB_STRIPE_RECONCILIATION_OPEN_TIMEOUT_SECONDS",
      read_timeout: "MCWEB_STRIPE_RECONCILIATION_READ_TIMEOUT_SECONDS",
      write_timeout: "MCWEB_STRIPE_RECONCILIATION_WRITE_TIMEOUT_SECONDS",
      max_network_retries: "MCWEB_STRIPE_RECONCILIATION_MAX_NETWORK_RETRIES",
      retry_delay:
        "MCWEB_STRIPE_RECONCILIATION_NETWORK_RETRY_DELAY_SECONDS"
    }.freeze
    DEFAULTS = {
      open_timeout: 5,
      read_timeout: 15,
      write_timeout: 5,
      max_network_retries: 1,
      retry_delay: 1
    }.freeze
    BOUNDS = {
      open_timeout: 1..5,
      read_timeout: 1..19,
      write_timeout: 1..5,
      max_network_retries: 0..1,
      retry_delay: 0..2
    }.freeze
    MAX_CONFIGURED_TIMEOUT_BUDGET_SECONDS = 60

    def initialize(
      environment: ENV,
      client_factory: ->(api_key) { Stripe::StripeClient.new(api_key) }
    )
      @environment = environment
      @client_factory = client_factory
    end

    def build(secret_key:)
      client = @client_factory.call(secret_key.to_s)
      configuration = client_configuration!(client)
      network_budget.to_h.except(:retry_delay).each do |attribute, value|
        configuration.public_send("#{attribute}=", value)
      end
      configuration.initial_network_retry_delay = network_budget.retry_delay
      configuration.max_network_retry_delay = network_budget.retry_delay
      client
    end

    def network_budget
      @network_budget ||= Budget.new(
        **DEFAULTS.to_h do |attribute, default|
          [ attribute, bounded_integer(attribute, default) ]
        end
      ).tap do |budget|
        if budget.configured_timeout_budget_seconds >
            MAX_CONFIGURED_TIMEOUT_BUDGET_SECONDS
          raise UnsupportedClientConfiguration,
            "Stripe reconciliation network timeout budget exceeds its safety bound."
        end
      end
    end

    private

    def bounded_integer(attribute, default)
      raw = @environment[ENVIRONMENT_KEYS.fetch(attribute)]
      return default if raw.blank?

      value = Integer(raw, 10)
      bounds = BOUNDS.fetch(attribute)
      value.clamp(bounds.begin, bounds.end)
    rescue ArgumentError, TypeError
      default
    end

    def client_configuration!(client)
      requestor = client.instance_variable_get(:@requestor)
      configuration = requestor&.config
      return configuration if configuration.is_a?(Stripe::StripeConfiguration)

      raise UnsupportedClientConfiguration,
        "This stripe-ruby client does not expose an isolated request configuration."
    end
  end
end
