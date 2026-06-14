# frozen_string_literal: true

module Payments
  class WebhookProcessor < ApplicationService
    def initialize(provider:, event_id:, event_type:, payload:, signature:, headers: {})
      @provider = provider.to_s
      @event_id = event_id.to_s
      @event_type = event_type.to_s
      @payload = payload
      @signature = signature
      @headers = headers
    end

    def call
      event = find_or_create_event
      return ServiceResult.success(event: event, idempotent: true) if event.status == "processed"

      adapter = Provider.for(@provider)
      payload_body = @payload.is_a?(String) ? @payload : @payload.to_json

      unless adapter.verify_webhook_signature(payload: payload_body, signature: @signature, headers: @headers)
        event.update!(status: "failed", error_message: "Invalid webhook signature.")
        return ServiceResult.failure(error: "Invalid webhook signature.")
      end

      result = adapter.process_webhook_event(event)

      if result.success?
        event.update!(status: "processed", processed_at: Time.current, error_message: nil)
      else
        event.update!(status: "failed", error_message: result.error)
      end

      result
    rescue Provider::UnknownProviderError => e
      ServiceResult.failure(error: e.message)
    end

    private

    def find_or_create_event
      Payments::WebhookEvent.find_or_create_by!(provider: @provider, event_id: @event_id) do |event|
        event.event_type = @event_type
        event.payload = normalize_payload
        event.status = "received"
      end
    end

    def normalize_payload
      case @payload
      when String
        JSON.parse(@payload)
      when Hash
        @payload
      else
        @payload.as_json
      end
    rescue JSON::ParserError
      { raw: @payload.to_s }
    end
  end
end
