# frozen_string_literal: true

module Administration
  # Fans a single Mcweb::Events event out to all matching webhook subscriptions.
  # Cheap no-op when there are no subscribers (the common case), so it adds no
  # overhead to core flows unless an integration has opted in.
  class WebhookFanout < ApplicationService
    def initialize(event:, payload:)
      @event = event.to_s
      @payload = payload
    end

    def call
      subscriptions = Administration::WebhookSubscription.for_event(@event).to_a
      return ServiceResult.success(skipped: :no_subscribers) if subscriptions.empty?

      body = Administration::SerializeEventPayload.call(event: @event, payload: @payload)
      subscriptions.each do |subscription|
        Administration::DeliverWebhookSubscriptionJob.perform_later(subscription.id, body)
      end
      ServiceResult.success(delivered: subscriptions.size)
    rescue StandardError => e
      Rails.logger.error("[WebhookFanout] #{@event}: #{e.class}: #{e.message}")
      ServiceResult.failure(error: e.message)
    end
  end
end
