# frozen_string_literal: true

module Payments
  class WebhookPayload
    class InvalidPayloadError < StandardError; end

    STRIPE_OBJECT_KEYS = %w[
      id
      object
      livemode
      payment_status
      amount_total
      amount_received
      amount
      currency
      client_reference_id
      payment_intent
    ].freeze
    STRIPE_METADATA_KEYS = %w[payment_record_id order_public_id].freeze
    FAKE_EVENT_TYPES = %w[payment.succeeded].freeze

    class << self
      def normalize(provider:, event_id:, event_type:, payload:)
        parsed = parse(payload)

        case provider.to_s
        when "stripe"
          normalize_stripe(
            parsed,
            event_id: event_id.to_s,
            event_type: event_type.to_s
          )
        when "fake"
          { "payment_id" => parsed["payment_id"].to_s.first(255) }
        else
          raise InvalidPayloadError, "Unsupported payment provider."
        end
      end

      def digest(payload, event_type: nil)
        envelope = {
          "event_type" => event_type.to_s,
          "payload" => payload.to_h.deep_stringify_keys
        }
        Digest::SHA256.hexdigest(JSON.generate(deep_sort(envelope)))
      end

      def replayable?(provider:, event_type:)
        case provider.to_s
        when "stripe"
          (
            Payments::StripeProvider::PAYMENT_SUCCEEDED_EVENTS +
            Payments::StripeProvider::PAYMENT_FAILED_EVENTS
          ).include?(event_type.to_s)
        when "fake"
          FAKE_EVENT_TYPES.include?(event_type.to_s)
        else
          false
        end
      end

      private

      def parse(payload)
        value =
          case payload
          when String then JSON.parse(payload)
          when Hash then payload
          else payload.as_json
          end

        raise InvalidPayloadError, "Webhook payload must be an object." unless value.respond_to?(:to_h)

        value.to_h.deep_stringify_keys
      rescue JSON::ParserError, NoMethodError
        raise InvalidPayloadError, "Webhook payload is invalid."
      end

      def normalize_stripe(payload, event_id:, event_type:)
        payload_id = payload["id"].to_s
        payload_type = payload["type"].to_s
        if payload_id.present? && !secure_match?(payload_id, event_id)
          raise InvalidPayloadError, "Stripe event ID mismatch."
        end
        if payload_type.blank? || !secure_match?(payload_type, event_type)
          raise InvalidPayloadError, "Stripe event type mismatch."
        end

        object = payload.dig("data", "object").to_h.deep_stringify_keys
        metadata = object.fetch("metadata", {}).to_h.deep_stringify_keys
        minimal_object = object.slice(*STRIPE_OBJECT_KEYS)
        minimal_object["metadata"] = metadata.slice(*STRIPE_METADATA_KEYS)

        {
          "type" => payload_type,
          "data" => {
            "object" => minimal_object
          }
        }
      end

      def secure_match?(left, right)
        return false unless left.bytesize == right.bytesize

        ActiveSupport::SecurityUtils.secure_compare(left, right)
      end

      def deep_sort(value)
        case value
        when Hash
          value.keys.sort.each_with_object({}) do |key, sorted|
            sorted[key] = deep_sort(value.fetch(key))
          end
        when Array
          value.map { |item| deep_sort(item) }
        else
          value
        end
      end
    end
  end
end
