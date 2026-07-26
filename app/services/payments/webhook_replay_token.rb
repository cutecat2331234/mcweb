# frozen_string_literal: true

module Payments
  class WebhookReplayToken
    PURPOSE = "payment_webhook_replay"
    EXPIRES_IN = 10.minutes

    class << self
      def issue(event)
        verifier.generate(
          token_payload(event),
          purpose: PURPOSE,
          expires_in: EXPIRES_IN
        )
      end

      def valid?(token, event)
        payload = verifier.verified(token.to_s, purpose: PURPOSE)
        return false unless payload.is_a?(Hash)

        expected = token_payload(event)
        expected.all? do |key, value|
          secure_value_match?(payload[key], value)
        end
      end

      private

      def token_payload(event)
        {
          "event_id" => event.id.to_s,
          "payload_digest" => event.payload_digest.to_s,
          "status" => event.status.to_s,
          "updated_at" => event.updated_at.utc.iso8601(6)
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
