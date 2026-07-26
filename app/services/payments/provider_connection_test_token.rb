# frozen_string_literal: true

module Payments
  class ProviderConnectionTestToken
    PURPOSE = "payment_provider_connection_test"
    EXPIRES_IN = 10.minutes

    class << self
      def issue(config)
        verifier.generate(
          token_payload(config),
          purpose: PURPOSE,
          expires_in: EXPIRES_IN
        )
      end

      def valid?(token, config)
        payload = verifier.verified(token.to_s, purpose: PURPOSE)
        return false unless payload.is_a?(Hash)

        expected = token_payload(config)
        expected.all? do |key, value|
          secure_value_match?(payload[key], value)
        end
      end

      private

      def token_payload(config)
        {
          "config_id" => config.id.to_s,
          "provider" => config.provider.to_s,
          "mode" => config.effective_mode,
          "credential_revision" => config.credential_revision,
          "updated_at" => config.updated_at.utc.iso8601(6)
        }
      end

      def verifier
        Rails.application.message_verifier(PURPOSE)
      end

      def secure_value_match?(left, right)
        left = left.to_s
        right = right.to_s
        left.bytesize == right.bytesize &&
          ActiveSupport::SecurityUtils.secure_compare(left, right)
      end
    end
  end
end
