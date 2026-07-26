# frozen_string_literal: true

require "timeout"

module Payments
  class TestProviderConnection < ApplicationService
    PERMISSION = "store.payments.connection_test"
    PROVIDER = "stripe"
    TIMEOUT_SECONDS = 5
    SAFE_ERROR_CODES = %w[
      authentication_failed
      account_history_unbound
      account_mismatch
      configuration_changed
      configuration_incomplete
      environment_mismatch
      internal_error
      invalid_confirmation
      invalid_response
      invalid_test_token
      developer_mode_fake_only
      permission_denied
      provider_error
      provider_unavailable
      rate_limited
      timeout
    ].freeze

    def initialize(
      actor:,
      token:,
      confirmation:,
      probe: Payments::StripeConnectionProbe,
      timeout_seconds: TIMEOUT_SECONDS,
      ip_address: nil,
      user_agent: nil
    )
      @actor = actor
      @token = token
      @confirmation = confirmation.to_s.strip
      @probe = probe
      @timeout_seconds = timeout_seconds
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return forbidden_result unless @actor&.permission?(PERMISSION)
      return failure("Type stripe to confirm the connection test.", "invalid_confirmation") unless confirmed?
      if Payments::Provider.developer_mode_fake_only?
        return failure(
          I18n.t(
            "mcweb.flash.payment_provider_connection_test_blocked_by_developer_mode"
          ),
          "developer_mode_fake_only"
        )
      end

      config = Payments::ProviderConfig.find_by(provider: PROVIDER)
      return failure("Stripe configuration is incomplete.", "configuration_incomplete") unless config
      return failure("The connection-test authorization expired or is invalid.", "invalid_test_token") unless token_valid?(config)
      return failure("Stripe configuration is incomplete.", "configuration_incomplete") unless config.configuration_complete?

      revision = config.credential_revision
      mode = config.effective_mode
      secret_key = config.credentials_hash.stringify_keys.fetch("secret_key")
      probe_result = run_probe(secret_key: secret_key, mode: mode)

      record_result(config, revision: revision, mode: mode, probe_result: probe_result)
    end

    private

    def run_probe(secret_key:, mode:)
      result = Timeout.timeout(@timeout_seconds) do
        @probe.call(secret_key: secret_key, expected_mode: mode)
      end
      return result if result.is_a?(ServiceResult) && result.failure?
      return normalized_probe_success(result, mode: mode) if result.is_a?(ServiceResult)

      failure("Stripe returned an invalid connection-test response.", "invalid_response")
    rescue Timeout::Error
      failure("The Stripe connection test timed out.", "timeout")
    rescue StandardError
      failure("The Stripe connection test could not be completed.", "internal_error")
    end

    def normalized_probe_success(result, mode:)
      value = result.value.to_h.symbolize_keys
      fingerprint = value[:account_fingerprint].to_s
      unless value[:mode].to_s == mode &&
          fingerprint.match?(Payments::ProviderConfig::SHA256_HEX_PATTERN)
        return failure(
          "Stripe returned an invalid connection-test response.",
          "invalid_response"
        )
      end

      ServiceResult.success(
        mode: mode,
        account_fingerprint: fingerprint
      )
    end

    def record_result(config, revision:, mode:, probe_result:)
      result = nil

      Payments::ProviderConfig.transaction do
        current = Payments::ProviderConfig.lock.find(config.id)
        unless secure_match?(current.credential_revision, revision)
          result = failure(
            "The Stripe configuration changed while the test was running.",
            "configuration_changed"
          )
          raise ActiveRecord::Rollback
        end

        account_result = account_binding_result(current, probe_result)
        status = account_result.success? ? "success" : "failed"
        error_code = account_result.success? ? nil : safe_error_code(account_result.code)
        attributes = {
          last_connection_tested_at: Time.current,
          last_connection_test_status: status,
          last_connection_test_error_code: error_code,
          last_connection_test_mode: mode,
          last_connection_tested_by: @actor,
          last_connection_test_credential_revision:
            (revision if account_result.success?)
        }
        if account_result.success? && current.account_fingerprint.blank?
          attributes[:account_fingerprint] =
            account_result.value.fetch(:account_fingerprint)
        end
        current.update!(attributes)

        Administration::AuditLogger.call(
          actor: @actor,
          action: "admin.payment_provider_connection_tested",
          resource: current,
          metadata: {
            provider: current.provider,
            mode: mode,
            enabled: current.enabled?,
            status: status,
            error_code: error_code,
            account_binding: current.stripe_account_bound? ? "bound" : "unbound",
            configuration_current: current.connection_test_current?
          }.compact,
          ip_address: @ip_address,
          user_agent: @user_agent
        )

        result =
          if account_result.success?
            ServiceResult.success(
              provider: current.provider,
              mode: mode,
              status: status,
              tested_at: current.last_connection_tested_at
            )
          else
            failure(error_message_for(error_code), error_code)
          end
      end

      result
    end

    def account_binding_result(config, probe_result)
      return probe_result if probe_result.failure?

      fingerprint = probe_result.value.fetch(:account_fingerprint)
      if config.account_fingerprint.present?
        return ServiceResult.success(account_fingerprint: fingerprint) if secure_match?(
          config.account_fingerprint,
          fingerprint
        )

        return failure(
          "The Stripe account does not match the account already bound to this installation.",
          "account_mismatch"
        )
      end

      if stripe_financial_history?
        return failure(
          "Stripe account identity cannot be bound automatically because financial history already exists.",
          "account_history_unbound"
        )
      end

      ServiceResult.success(account_fingerprint: fingerprint)
    end

    def stripe_financial_history?
      Payments::StripeFinancialHistory.exists?
    end

    def token_valid?(config)
      Payments::ProviderConnectionTestToken.valid?(@token, config)
    end

    def confirmed?
      secure_match?(@confirmation, PROVIDER)
    end

    def secure_match?(left, right)
      left = left.to_s
      right = right.to_s
      left.bytesize == right.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(left, right)
    end

    def safe_error_code(code)
      code = code.to_s
      SAFE_ERROR_CODES.include?(code) ? code : "provider_error"
    end

    def error_message_for(code)
      {
        "authentication_failed" => "Stripe rejected the configured credentials.",
        "account_history_unbound" => "Stripe account identity cannot be bound automatically because financial history already exists.",
        "account_mismatch" => "The Stripe account does not match the account already bound to this installation.",
        "environment_mismatch" => "Stripe returned a different environment than the configured mode.",
        "permission_denied" => "The Stripe key does not have the required read permission.",
        "provider_unavailable" => "Stripe could not be reached.",
        "rate_limited" => "Stripe rate-limited the connection test.",
        "timeout" => "The Stripe connection test timed out.",
        "invalid_response" => "Stripe returned an invalid connection-test response."
      }.fetch(code, "The Stripe connection test could not be completed.")
    end

    def failure(message, code)
      ServiceResult.failure(error: message, code: code)
    end

    def forbidden_result
      failure(
        "You do not have permission to test payment-provider connections.",
        "forbidden"
      )
    end
  end
end
