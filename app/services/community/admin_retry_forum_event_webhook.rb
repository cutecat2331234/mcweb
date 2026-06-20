# frozen_string_literal: true

module Community
  class AdminRetryForumEventWebhook < ApplicationService
    def initialize(delivery:)
      @delivery = delivery
    end

    def call
      payload = @delivery.request_payload
      return ServiceResult.failure(error: "webhook_payload_missing") if payload.blank?

      url = @delivery.url.presence || SiteSetting.get("forum.event_webhook_url", "").to_s.strip
      return ServiceResult.failure(error: "webhook_url_missing") if url.blank?
      return ServiceResult.failure(error: "webhook_url_private") unless UrlSafety.public_http_url?(url)

      secret = SiteSetting.get("forum.event_webhook_secret", "").to_s.strip.presence
      Community::DispatchForumEventWebhookJob.perform_later(url, payload, secret, delivery_id: @delivery.id, attempt: 1)
      ServiceResult.success(queued: true)
    end
  end
end
