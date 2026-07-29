# frozen_string_literal: true

require "openssl"

module Payments
  class StripeConnectionProbe < ApplicationService
    ACCOUNT_ID_PATTERN = /\Aacct_[A-Za-z0-9]{16,64}\z/
    ACCOUNT_FINGERPRINT_DOMAIN =
      "mcweb:payments:stripe-account-fingerprint:v1\x00".b.freeze

    class << self
      def account_fingerprint(account_id)
        account_id = account_id.to_s
        raise ArgumentError, "invalid Stripe account id" unless ACCOUNT_ID_PATTERN.match?(account_id)

        key = Lockbox.attribute_key(
          table: "payment_provider_configs",
          attribute: "account_fingerprint",
          encode: false
        )
        OpenSSL::HMAC.hexdigest(
          "SHA256",
          key,
          ACCOUNT_FINGERPRINT_DOMAIN + account_id.b
        )
      end
    end

    def initialize(secret_key:, expected_mode:)
      @secret_key = secret_key
      @expected_mode = expected_mode
    end

    def call
      client = Stripe::StripeClient.new(@secret_key)
      balance = client.v1.balance.retrieve
      livemode = stripe_value(balance, :livemode)
      return invalid_response unless [ true, false ].include?(livemode)

      actual_mode = livemode ? "live" : "test"
      unless actual_mode == @expected_mode
        return ServiceResult.failure(
          error: :stripe_returned_a_different_environment_than_the_configured_mode,
          code: "environment_mismatch"
        )
      end

      account_id = stripe_value(client.v1.accounts.retrieve_current, :id).to_s
      return invalid_response unless ACCOUNT_ID_PATTERN.match?(account_id)

      ServiceResult.success(
        mode: actual_mode,
        account_fingerprint: self.class.account_fingerprint(account_id)
      )
    rescue Stripe::AuthenticationError
      failure("Stripe rejected the configured credentials.", "authentication_failed")
    rescue Stripe::PermissionError
      failure("The Stripe key cannot read the required account data.", "permission_denied")
    rescue Stripe::RateLimitError
      failure("Stripe rate-limited the connection test.", "rate_limited")
    rescue Stripe::APIConnectionError
      failure("Stripe could not be reached.", "provider_unavailable")
    rescue Stripe::StripeError
      failure("Stripe could not complete the connection test.", "provider_error")
    end

    private

    def stripe_value(object, key)
      return object.public_send(key) if object.respond_to?(key)
      return object[key.to_s] if object.respond_to?(:[])

      nil
    end

    def invalid_response
      failure("Stripe returned an invalid connection-test response.", "invalid_response")
    end

    def failure(message, code)
      ServiceResult.failure(error: message, code: code)
    end
  end
end
