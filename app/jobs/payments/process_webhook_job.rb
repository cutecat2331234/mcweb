# frozen_string_literal: true

module Payments
  class ProcessWebhookJob < ApplicationJob
    queue_as :payments

    # Keyword compatibility keeps jobs serialized before this reliability
    # rollout executable while all newly enqueued jobs carry only a database ID.
    def perform(webhook_event_id: nil, source: "delivery", actor_id: nil, **legacy)
      result =
        if webhook_event_id
          event = Payments::WebhookEvent.find(webhook_event_id)
          Payments::ProcessStoredWebhook.call(
            event: event,
            source: source,
            actor_id: actor_id
          )
        else
          Payments::WebhookProcessor.call(**legacy)
        end

      schedule_retry(result)
      result
    end

    private

    def schedule_retry(result)
      event = result.value.to_h[:event]
      return unless result.failure? && event

      event.reload
      return unless event.failed? && event.next_retry_at.present?

      self.class.set(wait_until: event.next_retry_at).perform_later(
        webhook_event_id: event.id,
        source: "automatic"
      )
    end
  end
end
