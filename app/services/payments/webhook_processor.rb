# frozen_string_literal: true

module Payments
  class WebhookProcessor < ApplicationService
    STALE_PROCESSING_AFTER = Payments::WebhookEvent::PROCESSING_TIMEOUT

    def initialize(provider:, event_id:, event_type:, payload:, signature:, headers: {})
      @attributes = {
        provider: provider,
        event_id: event_id,
        event_type: event_type,
        payload: payload,
        signature: signature,
        headers: headers
      }
    end

    def call
      received = Payments::ReceiveWebhook.call(**@attributes)
      return received if received.failure?

      event = received.value.fetch(:event)
      unless received.value[:should_process]
        return ServiceResult.success(event: event, idempotent: true)
      end

      Payments::ProcessStoredWebhook.call(event: event, source: "delivery")
    end
  end
end
