# frozen_string_literal: true

module Payments
  class OperationsSerializer
    ORPHAN_REASONS = %w[order_cancelled order_expired].freeze
    TOKEN_PATTERN = /\A[a-zA-Z0-9_.:-]+\z/

    class << self
      def record(payment)
        {
          id: payment.id,
          order_id: payment.order.public_id,
          order_number: payment.order.order_number,
          provider: safe_token(payment.provider),
          provider_reference: masked_reference(payment.provider_payment_id),
          status: payment.status,
          amount_cents: payment.amount_cents,
          currency: safe_token(payment.currency),
          orphaned: payment.metadata["orphaned"] == true,
          orphan_reason: orphan_reason(payment.metadata["orphan_reason"]),
          created_at: timestamp(payment.created_at),
          updated_at: timestamp(payment.updated_at)
        }
      end

      def webhook(event)
        {
          id: event.id,
          provider: safe_token(event.provider),
          event_reference: masked_reference(event.event_id),
          event_type: safe_token(event.event_type),
          status: event.status,
          stale: stale_webhook?(event),
          error_recorded: event.error_message.present?,
          last_error_code: safe_error_code(event.last_error_code),
          attempt_count: event.attempt_count,
          retry_count: event.retry_count,
          manual_replay_count: event.manual_replay_count,
          next_retry_at: timestamp(event.next_retry_at),
          last_attempted_at: timestamp(event.last_attempted_at),
          dead_lettered_at: timestamp(event.dead_lettered_at),
          created_at: timestamp(event.created_at),
          updated_at: timestamp(event.updated_at),
          processed_at: timestamp(event.processed_at)
        }
      end

      def refund(refund)
        {
          id: refund.id,
          order_id: refund.order.public_id,
          order_number: refund.order.order_number,
          payment_record_id: refund.payment_record_id,
          provider: safe_token(refund.payment_record.provider),
          provider_reference: masked_reference(refund.provider_refund_id),
          status: refund.status,
          provider_status: safe_token(refund.provider_status, fallback: nil),
          provider_error_code: safe_error_code(refund.provider_error_code),
          amount_cents: refund.amount_cents,
          currency: safe_token(refund.order.currency),
          stale: refund.processing_stale?,
          processing_started_at: timestamp(refund.processing_started_at),
          created_at: timestamp(refund.created_at),
          updated_at: timestamp(refund.updated_at)
        }
      end

      def provider_status(status)
        {
          provider: safe_token(status.fetch(:provider)),
          configured: status.fetch(:configured),
          enabled: status.fetch(:enabled),
          checkout_ready: status.fetch(:checkout_ready),
          payment_counts: safe_counts(status.fetch(:payment_counts)),
          refund_counts: safe_counts(status.fetch(:refund_counts)),
          updated_at: timestamp(status[:updated_at])
        }
      end

      def filter_options(options)
        {
          providers: Array(options[:providers]).filter_map do |provider|
            safe_token(provider, fallback: nil)
          end,
          statuses: Array(options[:statuses]).filter_map do |status|
            safe_token(status, fallback: nil, max_length: 32)
          end,
          provider_statuses: Array(options[:provider_statuses]).filter_map do |status|
            safe_token(status, fallback: nil, max_length: 80)
          end
        }
      end

      def filters(filters)
        {
          provider: safe_token(filters[:provider], fallback: nil),
          status: safe_token(filters[:status], fallback: nil, max_length: 32),
          provider_status: safe_token(filters[:provider_status], fallback: nil),
          q: filters[:q]
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

      def safe_token(value, fallback: "unknown", max_length: 80)
        text = value.to_s
        return fallback if text.blank?
        return fallback if text.length > max_length || !TOKEN_PATTERN.match?(text)

        text
      end

      def safe_error_code(value)
        safe_token(value, fallback: value.present? ? "recorded" : nil, max_length: 64)
      end

      def safe_counts(counts)
        counts.each_with_object({}) do |(status, count), values|
          token = safe_token(status, fallback: nil, max_length: 32)
          values[token] = count.to_i if token
        end
      end

      def orphan_reason(value)
        value if ORPHAN_REASONS.include?(value.to_s)
      end

      def stale_webhook?(event)
        event.status.in?(%w[received processing]) &&
          (event.processing_started_at || event.updated_at) <
            Payments::OperationsQuery::WEBHOOK_STALE_AFTER.ago
      end

      def timestamp(value)
        value&.iso8601
      end
    end
  end
end
