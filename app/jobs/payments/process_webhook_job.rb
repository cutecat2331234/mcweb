# frozen_string_literal: true

module Payments
  class ProcessWebhookJob < ApplicationJob
    queue_as :payments

    def perform(provider:, event_id:, event_type:, payload:, signature:, headers: {})
      Payments::WebhookProcessor.call(
        provider: provider,
        event_id: event_id,
        event_type: event_type,
        payload: payload,
        signature: signature,
        headers: headers
      )
    end
  end
end
