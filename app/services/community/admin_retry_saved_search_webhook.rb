# frozen_string_literal: true

module Community
  class AdminRetrySavedSearchWebhook < ApplicationService
    def initialize(delivery:)
      @delivery = delivery
    end

    def call
      return ServiceResult.failure(error: "webhook_retry_not_failed") unless @delivery.status == "failed"
      return ServiceResult.failure(error: "webhook_retry_no_payload") if @delivery.request_payload.blank?

      search = @delivery.saved_search
      return ServiceResult.failure(error: "saved_search_missing") if search.blank?

      url = search.webhook_url.to_s.strip.presence || @delivery.url
      return ServiceResult.failure(error: "webhook_url_missing") if url.blank?
      return ServiceResult.failure(error: "webhook_url_private") unless UrlSafety.public_http_url?(url)

      payload = @delivery.request_payload.deep_stringify_keys
      secret = SiteSetting.get("forum.saved_search_webhook_secret", "").to_s.strip.presence
      Community::DispatchSavedSearchWebhookJob.perform_later(search.id, url, payload, secret: secret)
      ServiceResult.success(queued: true)
    end
  end
end
