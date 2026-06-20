# frozen_string_literal: true

module Payments
  class Provider
    class UnknownProviderError < StandardError; end

    def self.for(provider_name)
      case provider_name.to_s
      when "fake"
        FakeProvider.new
      when "stripe"
        StripeProvider.new
      else
        raise UnknownProviderError, "Unknown payment provider: #{provider_name}"
      end
    end

    def self.known?(provider_name)
      name = provider_name.to_s
      return false if Rails.env.production? && name == "fake"

      %w[fake stripe].include?(name)
    end

    def create_payment(payment_record)
      raise NotImplementedError
    end

    def verify_webhook_signature(payload:, signature:, headers: {})
      raise NotImplementedError
    end

    def process_webhook_event(event)
      raise NotImplementedError
    end

    def process_refund(refund)
      raise NotImplementedError
    end
  end
end
