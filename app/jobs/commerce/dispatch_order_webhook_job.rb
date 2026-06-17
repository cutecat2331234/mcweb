# frozen_string_literal: true

module Commerce
  class DispatchOrderWebhookJob < ApplicationJob
    queue_as :default

    MAX_ATTEMPTS = 3

    def perform(url, payload, secret = nil, delivery_id: nil, attempt: 1)
      delivery = find_or_create_delivery(url, payload, delivery_id, attempt)
      execute_request(delivery, url, payload, secret, attempt)
    end

  private

    def find_or_create_delivery(url, payload, delivery_id, attempt)
      if delivery_id.present?
        delivery = Commerce::OrderWebhookDelivery.find(delivery_id)
        delivery.update!(status: "pending", attempt_count: attempt) if delivery.status != "pending"
        delivery
      else
        Commerce::OrderWebhookDelivery.create!(
          event_type: payload["event"].to_s,
          order_public_id: payload["order_id"].to_s.presence,
          url: url,
          status: "pending",
          request_payload: payload,
          attempt_count: attempt
        )
      end
    end

    def execute_request(delivery, url, payload, secret, attempt)
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
      schedule_retry(url, payload, secret, delivery, attempt) unless success
    rescue StandardError => e
      delivery&.update!(
        status: "failed",
        response_body: "#{e.class}: #{e.message}".truncate(4000),
        attempt_count: attempt
      )
      schedule_retry(url, payload, secret, delivery, attempt) if delivery
      Rails.logger.warn("[DispatchOrderWebhookJob] #{e.class}: #{e.message}")
    end

    def schedule_retry(url, payload, secret, delivery, attempt)
      return if attempt >= MAX_ATTEMPTS

      next_attempt = attempt + 1
      wait = (2**attempt).minutes
      self.class.set(wait: wait).perform_later(
        url,
        payload,
        secret,
        delivery_id: delivery.id,
        attempt: next_attempt
      )
    end
  end
end
