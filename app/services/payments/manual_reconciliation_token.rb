# frozen_string_literal: true

module Payments
  class ManualReconciliationToken
    PURPOSE = "payment_manual_reconciliation"
    EXPIRES_IN = 10.minutes
    NONCE_PATTERN = /\A[0-9a-f]{32}\z/

    class << self
      def issue(actor:, config:, date:)
        verifier.generate(
          token_payload(actor: actor, config: config, date: date).merge(
            "nonce" => SecureRandom.hex(16)
          ),
          purpose: PURPOSE,
          expires_in: EXPIRES_IN
        )
      end

      def valid?(token, actor:, config:, date:)
        payload = verifier.verified(token.to_s, purpose: PURPOSE)
        return false unless payload.is_a?(Hash)
        return false unless payload["nonce"].to_s.match?(NONCE_PATTERN)

        token_payload(actor: actor, config: config, date: date).all? do |key, expected|
          secure_match?(payload[key], expected)
        end
      end

      def consume?(token, actor:, config:, date:)
        return false unless valid?(
          token,
          actor: actor,
          config: config,
          date: date
        )

        Administration::RateLimiter.call(
          key: "payment_manual_reconciliation_token:" \
            "#{Digest::SHA256.hexdigest(token.to_s)}",
          limit: 1,
          window: EXPIRES_IN,
          developer_mode_bypass: false
        ).success?
      end

      private

      def token_payload(actor:, config:, date:)
        {
          "actor_id" => actor&.id.to_s,
          "config_id" => config.id.to_s,
          "provider" => config.provider.to_s,
          "mode" => config.effective_mode.to_s,
          "updated_at" => config.updated_at.utc.iso8601(6),
          "date" => date.to_date.iso8601
        }
      end

      def verifier
        Rails.application.message_verifier(PURPOSE)
      end

      def secure_match?(left, right)
        left = left.to_s
        right = right.to_s
        left.bytesize == right.bytesize &&
          ActiveSupport::SecurityUtils.secure_compare(left, right)
      end
    end
  end
end
