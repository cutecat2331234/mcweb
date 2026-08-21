# frozen_string_literal: true

module Payments
  class FakeProvider < Provider
    def create_payment(payment_record, return_url_base: nil)
      provider_payment_id = nil
      payment_record.with_lock do
        provider_payment_id = payment_record.provider_payment_id.presence || "fake_#{SecureRandom.alphanumeric(16)}"
        payment_record.update!(provider_payment_id: provider_payment_id) if payment_record.provider_payment_id.blank?
      end
      ServiceResult.success(payment_record: payment_record, checkout_url: "#{Mcweb::Paths::APP_PREFIX}/payments/fake/#{provider_payment_id}")
    end

    def verify_webhook_signature(payload:, signature:, headers: {})
      secret = webhook_secret
      return false if secret.blank?

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
      ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)
    end

    def process_webhook_event(event)
      return process_dispute_event(event) if event.event_type.to_s.start_with?("dispute.")

      payment_record = Payments::Record.find_by(
        provider: "fake",
        provider_payment_id: event.payload.dig("payment_id")
      )
      unless payment_record
        return ServiceResult.failure(
          error: :payment_not_found,
          code: "payment_not_found"
        )
      end

      result = Commerce::ConfirmPayment.call(
        payment_record: payment_record,
        provider_payment_id: event.payload.dig("payment_id"),
        metadata: { webhook_event_id: event.event_id }
      )

      result
    end

    def process_refund(refund)
      ServiceResult.success(
        refund: refund,
        provider_refund_id: "fake_refund_#{refund.id}",
        provider_status: "succeeded",
        provider_metadata: {}
      )
    end

    private

    def process_dispute_event(event)
      payment_record = Payments::Record.find_by(
        provider: "fake",
        provider_payment_id: event.payload["payment_id"]
      )
      return ServiceResult.failure(error: :payment_not_found, code: "payment_not_found") unless payment_record

      Commerce::Disputes::ApplyChannelEvent.call(
        provider: "fake",
        provider_event_id: event.event_id,
        provider_dispute_id: event.payload["dispute_id"],
        payment_record: payment_record,
        event_type: event.event_type,
        provider_status: event.payload["status"],
        amount_cents: event.payload["amount"],
        currency: event.payload["currency"],
        occurred_at: event.payload["occurred_at"].presence || event.created_at,
        sequence: event.payload["sequence"],
        evidence_due_at: event.payload["evidence_due_at"],
        risk_level: event.payload["risk_level"],
        reason_code: event.payload["reason"],
        kind: "dispute",
        payload_digest: event.payload_digest,
        webhook_event: event
      )
    end

    def webhook_secret
      secret = Rails.application.credentials.dig(:payments, :fake, :webhook_secret)
      return secret if secret.present?

      return "fake_webhook_secret" if Rails.env.development? || Rails.env.test?

      nil
    end
  end
end
