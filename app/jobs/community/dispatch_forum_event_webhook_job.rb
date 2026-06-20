# frozen_string_literal: true

module Community
  class DispatchForumEventWebhookJob < ApplicationJob
    queue_as :default

    MAX_ATTEMPTS = 3

    def perform(url, payload, secret = nil, delivery_id: nil, attempt: 1)
      delivery = find_or_create_delivery(url, payload, delivery_id, attempt)
      execute_request(delivery, url, payload, secret, attempt)
    end

  private

    def find_or_create_delivery(url, payload, delivery_id, attempt)
      if delivery_id.present?
        delivery = Community::EventWebhookDelivery.find(delivery_id)
        delivery.update!(status: "pending", attempt_count: attempt) if delivery.status != "pending"
        delivery
      else
        Community::EventWebhookDelivery.create!(
          event_type: payload["event"].to_s,
          forum_topic_id: topic_id_from_payload(payload),
          forum_post_id: post_id_from_payload(payload),
          url: url,
          status: "pending",
          request_payload: payload,
          attempt_count: attempt
        )
      end
    end

    def topic_id_from_payload(payload)
      public_id = payload.dig("topic", "id").to_s
      return nil if public_id.blank? || public_id.start_with?("test_")

      Community::Topic.find_by(public_id: public_id)&.id
    end

    def post_id_from_payload(payload)
      id = payload.dig("post", "id").to_i
      return nil if id <= 0

      Community::Post.exists?(id) ? id : nil
    end

    def execute_request(delivery, url, payload, secret, attempt)
      unless UrlSafety.public_http_url?(url)
        delivery.update!(
          status: "failed",
          response_body: "blocked: private or invalid URL",
          attempt_count: attempt
        )
        return
      end

      uri = URI.parse(url)
      body = payload.to_json
      headers = { "Content-Type" => "application/json" }
      signature = WebhookSignature.header_for(secret, body)
      headers["X-McWeb-Signature"] = signature if signature.present?

      response = UrlSafety.safe_http_post(uri, body: body, headers: headers, open_timeout: 5, read_timeout: 10)
      raise StandardError, "Blocked or unreachable URL" if response.nil?

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
      Rails.logger.warn("[DispatchForumEventWebhookJob] #{e.class}: #{e.message}")
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
