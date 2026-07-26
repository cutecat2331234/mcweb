# frozen_string_literal: true

module Payments
  class ReconciliationSerializer
    TOKEN_PATTERN = /\A[a-zA-Z0-9_.:-]+\z/

    class << self
      def discrepancy(discrepancy, action: nil)
        {
          id: discrepancy.public_id,
          order_id: discrepancy.order&.public_id,
          order_number: discrepancy.order&.order_number,
          provider: safe_token(discrepancy.provider),
          mode: safe_token(discrepancy.mode, max_length: 16),
          subject_type: safe_token(discrepancy.subject_type, max_length: 16),
          kind: safe_token(discrepancy.kind),
          reference: safe_reference(discrepancy.reference_masked),
          status: safe_token(discrepancy.status, max_length: 24),
          local_status: safe_token(discrepancy.local_status, fallback: nil),
          provider_status: safe_token(discrepancy.provider_status, fallback: nil),
          local_amount_cents: discrepancy.local_amount_cents,
          provider_amount_cents: discrepancy.provider_amount_cents,
          local_currency: safe_token(discrepancy.local_currency, fallback: nil, max_length: 3),
          provider_currency: safe_token(
            discrepancy.provider_currency,
            fallback: nil,
            max_length: 3
          ),
          run: run(discrepancy.run),
          review_note: sanitized_note(discrepancy.review_note),
          reviewed_by: discrepancy.reviewed_by&.username,
          reviewed_at: timestamp(discrepancy.reviewed_at),
          first_seen_at: timestamp(discrepancy.first_seen_at),
          last_seen_at: timestamp(discrepancy.last_seen_at),
          action: action
        }.compact
      end

      def run(run)
        {
          id: run.id,
          provider: safe_token(run.provider),
          mode: safe_token(run.mode, max_length: 16),
          status: safe_token(run.status, max_length: 24),
          phase: safe_token(run.phase, max_length: 24),
          window_start: timestamp(run.window_start),
          window_end: timestamp(run.window_end),
          payments_checked: run.payments_checked,
          refunds_checked: run.refunds_checked,
          discrepancies_count: run.discrepancies_count,
          attempt_count: run.attempt_count,
          failure_code: safe_token(run.failure_code, fallback: nil),
          started_at: timestamp(run.started_at),
          completed_at: timestamp(run.completed_at)
        }.compact
      end

      def filters(filters)
        {
          status: safe_token(filters[:status], fallback: nil),
          kind: safe_token(filters[:kind], fallback: nil),
          subject_type: safe_token(filters[:subject_type], fallback: nil),
          provider: safe_token(filters[:provider], fallback: nil),
          mode: safe_token(filters[:mode], fallback: nil),
          q: filters[:q]
        }
      end

      def filter_options(options)
        {
          statuses: safe_tokens(options[:statuses]),
          kinds: safe_tokens(options[:kinds]),
          subject_types: safe_tokens(options[:subject_types]),
          providers: safe_tokens(options[:providers]),
          modes: safe_tokens(options[:modes])
        }
      end

      private

      def safe_tokens(values)
        Array(values).filter_map { |value| safe_token(value, fallback: nil) }
      end

      def safe_token(value, fallback: "unknown", max_length: 80)
        text = value.to_s
        return fallback if text.blank?
        return fallback if text.length > max_length || !TOKEN_PATTERN.match?(text)

        text
      end

      def safe_reference(value)
        text = value.to_s
        return if text.blank? || text.length > 100
        return unless text.match?(/\A[a-zA-Z0-9_-]*•{4}[a-zA-Z0-9]{4}\z/)

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
