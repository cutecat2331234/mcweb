# frozen_string_literal: true

module Commerce
  class AdminRetryOrderWebhook < ApplicationService
    def initialize(delivery:)
      @delivery = delivery
    end

    def call
      return ServiceResult.failure(error: "webhook_retry_not_failed") unless @delivery.status == "failed"
      return ServiceResult.failure(error: "webhook_retry_no_payload") if @delivery.request_payload.blank?

      url = @delivery.url.presence || SiteSetting.get("store.order_webhook_url", "").to_s.strip
      return ServiceResult.failure(error: "webhook_url_missing") if url.blank?
      return ServiceResult.failure(error: "webhook_url_private") unless UrlSafety.public_http_url?(url)

      payload = @delivery.request_payload.deep_stringify_keys
      secret = SiteSetting.get("store.order_webhook_secret", "").to_s.strip.presence
      # Reuse the existing delivery row (like the automatic retry path) instead of
      # creating a duplicate and leaving the original stuck on "failed".
      Commerce::DispatchOrderWebhookJob.perform_later(url, payload, secret, delivery_id: @delivery.id, attempt: 1)
      ServiceResult.success(queued: true)
    end
  end
end
