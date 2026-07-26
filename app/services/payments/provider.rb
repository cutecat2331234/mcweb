# frozen_string_literal: true

module Payments
  class Provider
    class UnknownProviderError < StandardError; end

    def self.for(provider_name)
      unless known?(provider_name)
        raise UnknownProviderError, "Unknown or unavailable payment provider: #{provider_name}"
      end

      case provider_name.to_s
      when "fake"
        FakeProvider.new
      when "stripe"
        StripeProvider.new
      end
    end

    def self.known?(provider_name)
      name = provider_name.to_s
      return name == "fake" if developer_mode_fake_only?
      return false if Rails.env.production? && name == "fake"

      %w[fake stripe].include?(name)
    end

    def self.developer_mode_fake_only?
      Mcweb::DeveloperMode.enabled? &&
        Mcweb::DeveloperMode.integration(:payments) == :fake
    end

    def create_payment(payment_record, return_url_base: nil)
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
