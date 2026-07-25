# frozen_string_literal: true

module Administration
  # Delivers a serialized event payload to a single webhook subscription, HMAC-signed.
  class DeliverWebhookSubscriptionJob < ApplicationJob
    queue_as :default

    def perform(subscription_id, payload)
      subscription = Administration::WebhookSubscription.find_by(id: subscription_id)
      return unless subscription&.active?

      payload = Administration::SerializeEventPayload.sanitize_envelope(payload)
      return if payload.blank?
      return unless subscription.event == Administration::WebhookSubscription::WILDCARD ||
        subscription.event == payload["event"]
      return unless Community::ForumEventWebhookPolicy.exportable_envelope?(payload)

      body = payload.to_json
      unless UrlSafety.public_http_url?(subscription.url)
        subscription.record_result!(success: false, status: "blocked")
        return
      end

      headers = { "Content-Type" => "application/json", "X-McWeb-Event" => payload["event"].to_s }
      signature = WebhookSignature.header_for(subscription.secret, body)
      headers["X-McWeb-Signature"] = signature if signature.present?

      response = UrlSafety.safe_http_post(URI.parse(subscription.url), body: body, headers: headers, open_timeout: 5, read_timeout: 10)
      if response.nil?
        subscription.record_result!(success: false, status: "unreachable")
        return
      end

      code = response.code.to_i
      subscription.record_result!(success: code.between?(200, 299), status: code.to_s)
    rescue StandardError => e
      subscription&.record_result!(success: false, status: "error")
      Rails.logger.warn("[DeliverWebhookSubscriptionJob] #{e.class}: #{e.message}")
    end
  end
end
