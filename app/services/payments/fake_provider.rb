# frozen_string_literal: true

module Payments
  class FakeProvider < Provider
    def create_payment(payment_record)
      provider_payment_id = "fake_#{SecureRandom.alphanumeric(16)}"
      payment_record.update!(provider_payment_id: provider_payment_id)
      ServiceResult.success(payment_record: payment_record, checkout_url: "/payments/fake/#{provider_payment_id}")
    end

    def verify_webhook_signature(payload:, signature:, headers: {})
      expected = OpenSSL::HMAC.hexdigest("SHA256", webhook_secret, payload)
      ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)
    end

    def process_webhook_event(event)
      payment_record = Payments::Record.find_by(
        provider: "fake",
        provider_payment_id: event.payload.dig("payment_id")
      )
      return ServiceResult.failure(error: "Payment record not found.") unless payment_record

      result = Commerce::ConfirmPayment.call(
        payment_record: payment_record,
        provider_payment_id: event.payload.dig("payment_id"),
        metadata: { webhook_event_id: event.event_id }
      )

      result
    end

    def process_refund(refund)
      refund.update!(status: "completed") if refund.status == "pending"
      ServiceResult.success(refund)
    end

    private

    def webhook_secret
      Rails.application.credentials.dig(:payments, :fake, :webhook_secret) || "fake_webhook_secret"
    end
  end
end
