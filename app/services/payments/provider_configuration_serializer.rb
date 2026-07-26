# frozen_string_literal: true

module Payments
  class ProviderConfigurationSerializer
    SAFE_ERROR_CODE = /\A[a-z0-9_]{1,64}\z/

    class << self
      def call(config:, webhook_check:, connection_test_token: nil, connection_test_allowed: false)
        state = config.safe_configuration_state

        {
          provider: state.fetch(:provider),
          enabled: state.fetch(:enabled),
          mode: state.fetch(:mode),
          mode_explicit: state.fetch(:mode_explicit),
          mode_consistent: config.mode_consistent?,
          configuration_complete: state.fetch(:configuration_complete),
          checkout_ready: state.fetch(:checkout_ready),
          account_binding: {
            bound: state.fetch(:account_bound),
            connection_current: state.fetch(:connection_test_current)
          },
          credentials: {
            secret_key: {
              configured: state.fetch(:secret_key_configured)
            },
            webhook_secret: {
              configured: state.fetch(:webhook_secret_configured)
            }
          },
          webhook: webhook_check,
          connection_test: {
            allowed: connection_test_allowed,
            token: connection_test_token,
            last_status: config.last_connection_test_status,
            last_error_code: safe_error_code(config.last_connection_test_error_code),
            last_mode: config.last_connection_test_mode,
            last_tested_at: timestamp(config.last_connection_tested_at),
            current: config.connection_test_current?
          }
        }
      end

      private

      def safe_error_code(value)
        text = value.to_s
        return nil if text.blank?

        SAFE_ERROR_CODE.match?(text) ? text : "recorded"
      end

      def timestamp(value)
        value&.iso8601
      end
    end
  end
end
