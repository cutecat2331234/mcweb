# frozen_string_literal: true

module Payments
  class StripeAccountBindingPreflight < ApplicationService
    RELEASE_BLOCKED_CODE = "stripe_account_binding_release_blocked"

    def call
      history_present = Payments::StripeFinancialHistory.exists?
      account_bound = account_bound?
      provider_enabled = provider_enabled?

      if history_present && !account_bound
        return ServiceResult.failure(
          error: "Release blocked: Stripe financial history exists without a verified account binding.",
          code: RELEASE_BLOCKED_CODE,
          value: {
            account_bound: false,
            financial_history_present: true,
            provider_enabled: provider_enabled
          }
        )
      end

      if provider_enabled && !account_bound
        return ServiceResult.failure(
          error: "Release blocked: disable Stripe before establishing the first verified account binding.",
          code: "stripe_account_binding_disable_required",
          value: {
            account_bound: false,
            financial_history_present: false,
            provider_enabled: true
          }
        )
      end

      ServiceResult.success(
        account_bound: account_bound,
        financial_history_present: history_present,
        provider_enabled: provider_enabled
      )
    end

    private

    def account_bound?
      config = provider_config
      return false unless config

      fingerprint = config.attributes["account_fingerprint"].to_s
      fingerprint.match?(Payments::ProviderConfig::SHA256_HEX_PATTERN)
    end

    def provider_enabled?
      provider_config&.enabled? || false
    end

    def provider_config
      @provider_config ||=
        Payments::ProviderConfig.find_by(provider: "stripe")
    end
  end
end
