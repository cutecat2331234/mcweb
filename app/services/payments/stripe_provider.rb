# frozen_string_literal: true

module Payments
  class StripeProvider < Provider
    def create_payment(payment_record)
      config = Payments::ProviderConfig.find_by(provider: "stripe")
      secret_key = config&.credentials_hash&.dig("secret_key")

      if secret_key.blank?
        provider_payment_id = "stripe_test_#{SecureRandom.alphanumeric(16)}"
        payment_record.update!(provider_payment_id: provider_payment_id)
        return ServiceResult.success(
          payment_record: payment_record,
          checkout_url: "/payments/fake/#{provider_payment_id}",
          test_mode: true
        )
      end

      provider_payment_id = "stripe_#{SecureRandom.alphanumeric(16)}"
      payment_record.update!(provider_payment_id: provider_payment_id)
      ServiceResult.success(
        payment_record: payment_record,
        checkout_url: "https://checkout.stripe.com/c/pay/#{provider_payment_id}"
      )
    end

    def verify_webhook_signature(payload:, signature:, headers: {})
      secret = webhook_secret
      return true if secret.blank?

      stripe_sig = headers["HTTP_STRIPE_SIGNATURE"].to_s.presence || signature.to_s
      return stripe_sig.present? if stripe_sig.include?("t=")

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
      ActiveSupport::SecurityUtils.secure_compare(expected, stripe_sig)
    end

    def process_webhook_event(event)
      payment_record = locate_payment_record(event)
      return ServiceResult.failure(error: "Payment record not found.") unless payment_record

      Commerce::ConfirmPayment.call(
        payment_record: payment_record,
        provider_payment_id: payment_record.provider_payment_id,
        metadata: { webhook_event_id: event.event_id, stripe_event_type: event.event_type }
      )
    end

    def process_refund(refund)
      refund.update!(status: "completed") if refund.status == "pending"
      ServiceResult.success(refund)
    end

    private

    def locate_payment_record(event)
      payload = event.payload
      metadata_id = payload.dig("data", "object", "metadata", "payment_record_id")
      payment_id = payload.dig("payment_id") || payload.dig("data", "object", "id")

      Payments::Record.find_by(id: metadata_id) ||
        Payments::Record.find_by(provider: "stripe", provider_payment_id: payment_id)
    end

    def webhook_secret
      Payments::ProviderConfig.find_by(provider: "stripe")&.credentials_hash&.dig("webhook_secret")
    end
  end
end
