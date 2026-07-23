# frozen_string_literal: true

# Bridge the in-process Mcweb::Events bus to outbound webhook subscriptions.
# Registered once at boot; each listener queries subscriptions lazily when an
# event fires (no DB access at boot), and is a no-op when there are no subscribers.
Rails.application.config.after_initialize do
  Mcweb::Events::CATALOG.each do |event|
    Mcweb::Events.subscribe(event) do |payload|
      Administration::WebhookFanout.call(event: event, payload: payload)
    end
  end
end
