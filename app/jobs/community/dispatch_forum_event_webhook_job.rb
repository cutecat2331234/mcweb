# frozen_string_literal: true

module Community
  class DispatchForumEventWebhookJob < ApplicationJob
    queue_as :default

    MAX_ATTEMPTS = 3

    # The third positional argument is retained only so jobs queued by older
    # releases can still deserialize. New jobs load the secret at execution time
    # instead of persisting it in the queue.
    def perform(url, payload, _legacy_secret = nil, delivery_id: nil, attempt: 1)
      existing_delivery = Community::EventWebhookDelivery.find_by(id: delivery_id) if delivery_id.present?
      safe_payload = sanitize_payload(payload, existing_delivery)
      return reject_invalid_payload(existing_delivery, attempt) if safe_payload.empty?
      unless Community::ForumEventWebhookPolicy.exportable_payload?(
        payload: safe_payload,
        delivery: existing_delivery
      )
        return reject_private_payload(existing_delivery, safe_payload, attempt)
      end

      effective_url = existing_delivery&.url.presence || url.to_s.strip
      return if effective_url.blank?

      delivery = find_or_create_delivery(effective_url, safe_payload, existing_delivery, attempt)
      execute_request(delivery, effective_url, safe_payload, attempt)
    end

  private

    def sanitize_payload(payload, delivery)
      Community::BuildForumEventWebhookPayload.sanitize(
        payload,
        event_type: delivery&.event_type,
        topic_id: delivery&.topic&.public_id,
        post_id: delivery&.forum_post_id,
        occurred_at: payload.to_h.with_indifferent_access[:occurred_at]
      )
    rescue NoMethodError
      {}
    end

    def reject_invalid_payload(delivery, attempt)
      delivery&.update!(
        status: "failed",
        request_payload: {},
        response_body: "blocked: invalid forum event payload",
        attempt_count: attempt
      )
      nil
    end

    def reject_private_payload(delivery, payload, attempt)
      delivery&.update!(
        status: "failed",
        request_payload: payload,
        response_body: "blocked: private forum resource",
        attempt_count: attempt
      )
      nil
    end

    def find_or_create_delivery(url, payload, delivery, attempt)
      if delivery
        delivery.update!(
          status: "pending",
          request_payload: payload,
          attempt_count: attempt
        )
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

    def execute_request(delivery, url, payload, attempt)
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
      signature = WebhookSignature.header_for(webhook_secret, body)
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
      schedule_retry(delivery, attempt) unless success
    rescue StandardError => e
      delivery&.update!(
        status: "failed",
        response_body: "#{e.class}: #{e.message}".truncate(4000),
        attempt_count: attempt
      )
      schedule_retry(delivery, attempt) if delivery
      Rails.logger.warn("[DispatchForumEventWebhookJob] #{e.class}: #{e.message}")
    end

    def schedule_retry(delivery, attempt)
      return if attempt >= MAX_ATTEMPTS

      next_attempt = attempt + 1
      wait = (2**attempt).minutes
      self.class.set(wait: wait).perform_later(
        delivery.url,
        delivery.request_payload,
        delivery_id: delivery.id,
        attempt: next_attempt
      )
    end

    def webhook_secret
      SiteSetting.get("forum.event_webhook_secret", "").to_s.strip.presence
    end
  end
end
