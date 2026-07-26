# frozen_string_literal: true

module Payments
  class ReconciliationReviewToken
    PURPOSE = "payment_reconciliation_review"
    EXPIRES_IN = 10.minutes

    class << self
      def issue(discrepancy)
        verifier.generate(
          token_payload(discrepancy),
          purpose: PURPOSE,
          expires_in: EXPIRES_IN
        )
      end

      def valid?(token, discrepancy)
        payload = verifier.verified(token.to_s, purpose: PURPOSE)
        return false unless payload.is_a?(Hash)

        token_payload(discrepancy).all? do |key, expected|
          secure_match?(payload[key], expected)
        end
      end

      private

      def token_payload(discrepancy)
        {
          "discrepancy_id" => discrepancy.id.to_s,
          "public_id" => discrepancy.public_id.to_s,
          "run_id" => discrepancy.run_id.to_s,
          "fingerprint" => discrepancy.fingerprint.to_s,
          "first_seen_at" => discrepancy.first_seen_at.utc.iso8601(6),
          "status" => discrepancy.status.to_s,
          "lock_version" => discrepancy.lock_version.to_s,
          "updated_at" => discrepancy.updated_at.utc.iso8601(6)
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
