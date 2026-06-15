# frozen_string_literal: true

module Community
  class DispatchSavedSearchWebhookJob < ApplicationJob
    queue_as :default

    MAX_ATTEMPTS = 3

    def perform(saved_search_id, url, payload, delivery_id: nil, attempt: 1, secret: nil)
      secret = secret.presence || forum_webhook_secret
      delivery = find_or_create_delivery(saved_search_id, url, payload, delivery_id, attempt)
      execute_request(delivery, url, payload, saved_search_id, attempt, secret)
    end

  private

    def forum_webhook_secret
      SiteSetting.get("forum.saved_search_webhook_secret", "").to_s.strip.presence
    end

    def find_or_create_delivery(saved_search_id, url, payload, delivery_id, attempt)
      if delivery_id.present?
        delivery = Community::SavedSearchWebhookDelivery.find(delivery_id)
        delivery.update!(status: "pending", attempt_count: attempt) if delivery.status != "pending"
        delivery
      else
        Community::SavedSearchWebhookDelivery.create!(
          saved_search_id: saved_search_id,
          event_type: payload["event"].to_s,
          url: url,
          status: "pending",
          request_payload: payload,
          attempt_count: attempt
        )
      end
    end

    def execute_request(delivery, url, payload, saved_search_id, attempt, secret)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 10

      body = payload.to_json
      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request.body = body
      signature = WebhookSignature.header_for(secret, body)
      request["X-McWeb-Signature"] = signature if signature.present?

      response = http.request(request)
      success = response.code.to_i.between?(200, 299)
      delivery.update!(
        response_code: response.code.to_i,
        response_body: response.body.to_s.truncate(4000),
        status: success ? "success" : "failed",
        attempt_count: attempt
      )
      schedule_retry(saved_search_id, url, payload, delivery, attempt, secret) unless success
    rescue StandardError => e
      delivery&.update!(
        status: "failed",
        response_body: "#{e.class}: #{e.message}".truncate(4000),
        attempt_count: attempt
      )
      schedule_retry(saved_search_id, url, payload, delivery, attempt, secret) if delivery
      Rails.logger.warn("[DispatchSavedSearchWebhookJob] #{e.class}: #{e.message}")
    end

    def schedule_retry(saved_search_id, url, payload, delivery, attempt, secret)
      return if attempt >= MAX_ATTEMPTS

      next_attempt = attempt + 1
      wait = (2**attempt).minutes
      self.class.set(wait: wait).perform_later(
        saved_search_id,
        url,
        payload,
        delivery_id: delivery.id,
        attempt: next_attempt,
        secret: secret
      )
    end
  end
end
