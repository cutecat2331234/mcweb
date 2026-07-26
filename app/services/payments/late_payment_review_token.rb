# frozen_string_literal: true

module Payments
  class LatePaymentReviewToken
    PURPOSE = "payment_late_payment_review"
    EXPIRES_IN = 10.minutes

    class << self
      def issue(review_case)
        verifier.generate(
          token_payload(review_case),
          purpose: PURPOSE,
          expires_in: EXPIRES_IN
        )
      end

      def valid?(token, review_case)
        payload = verifier.verified(token.to_s, purpose: PURPOSE)
        return false unless payload.is_a?(Hash)

        token_payload(review_case).all? do |key, value|
          secure_value_match?(payload[key], value)
        end
      end

      private

      def token_payload(review_case)
        {
          "case_id" => review_case.id.to_s,
          "payment_record_id" => review_case.payment_record_id.to_s,
          "webhook_event_id" => review_case.payment_webhook_event_id.to_s,
          "order_id" => review_case.store_order_id.to_s,
          "created_at" => review_case.created_at.utc.iso8601(6)
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
