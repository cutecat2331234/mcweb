# frozen_string_literal: true

module Payments
  class ReconciliationConfigBinding
    PURPOSE = "payment_reconciliation_config_binding"
    DIGEST_PATTERN = /\A[0-9a-f]{64}\z/

    class << self
      def generate(config:, run:)
        OpenSSL::HMAC.hexdigest(
          "SHA256",
          signing_key,
          payload(config: config, run: run)
        )
      end

      def valid?(digest, config:, run:)
        candidate = digest.to_s
        return false unless candidate.match?(DIGEST_PATTERN)

        expected = generate(config: config, run: run)
        ActiveSupport::SecurityUtils.secure_compare(candidate, expected)
      end

      private

      def payload(config:, run:)
        [
          config.id,
          config.provider,
          config.effective_mode,
          config.credential_revision,
          config.account_fingerprint,
          run.id,
          run.provider,
          run.mode,
          run.window_start.utc.iso8601(6),
          run.window_end.utc.iso8601(6)
        ].join("\0")
      end

      def signing_key
        Rails.application.key_generator.generate_key(PURPOSE, 32)
      end
    end
  end
end
