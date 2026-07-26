# frozen_string_literal: true

module Payments
  class LatePaymentCaseSerializer
    TOKEN_PATTERN = /\A[a-zA-Z0-9_.:-]+\z/

    class << self
      def call(review_case, action: nil)
        {
          id: review_case.id,
          order_id: review_case.order.public_id,
          order_number: review_case.order.order_number,
          provider: safe_token(review_case.provider),
          payment_reference: masked_reference(review_case.payment_record.provider_payment_id),
          webhook_reference: masked_reference(review_case.webhook_event.event_id),
          webhook_event_type: safe_token(review_case.webhook_event.event_type),
          status: review_case.status,
          reason: review_case.reason,
          amount_cents: review_case.amount_cents,
          currency: safe_token(review_case.currency),
          disposition: review_case.disposition,
          review_note: sanitized_note(review_case.review_note),
          acknowledged_by: review_case.acknowledged_by&.username,
          acknowledged_at: timestamp(review_case.acknowledged_at),
          created_at: timestamp(review_case.created_at),
          updated_at: timestamp(review_case.updated_at),
          action: action
        }.compact
      end

      def filters(filters)
        {
          status: safe_token(filters[:status], fallback: nil, max_length: 32),
          reason: safe_token(filters[:reason], fallback: nil, max_length: 32),
          provider: safe_token(filters[:provider], fallback: nil),
          q: filters[:q]
        }
      end

      def filter_options(options)
        {
          statuses: safe_tokens(options[:statuses], max_length: 32),
          reasons: safe_tokens(options[:reasons], max_length: 32),
          providers: safe_tokens(options[:providers])
        }
      end

      private

      def masked_reference(value)
        text = value.to_s
        return nil if text.blank?
        return "••••" if text.length <= 4

        prefix = text.include?("_") ? "#{text.split('_', 2).first}_" : ""
        "#{prefix}••••#{text.last(4)}"
      end

      def safe_tokens(values, max_length: 80)
        Array(values).filter_map do |value|
          safe_token(value, fallback: nil, max_length: max_length)
        end
      end

      def safe_token(value, fallback: "unknown", max_length: 80)
        text = value.to_s
        return fallback if text.blank?
        return fallback if text.length > max_length || !TOKEN_PATTERN.match?(text)

        text
      end

      def sanitized_note(value)
        value.to_s.gsub(/[[:cntrl:]]/, " ").squish.first(1_000).presence
      end

      def timestamp(value)
        value&.iso8601
      end
    end
  end
end
