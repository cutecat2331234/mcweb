# frozen_string_literal: true

module Community
  class AdminRetryForumEventWebhook < ApplicationService
    def initialize(delivery:)
      @delivery = delivery
    end

    def call
      return ServiceResult.failure(error: "webhook_retry_not_failed") unless @delivery.status == "failed"

      payload = Community::BuildForumEventWebhookPayload.sanitize(
        @delivery.request_payload,
        event_type: @delivery.event_type,
        topic_id: @delivery.topic&.public_id,
        post_id: @delivery.forum_post_id
      )
      return ServiceResult.failure(error: "webhook_payload_missing") if payload.blank?
      unless Community::ForumEventWebhookPolicy.exportable_payload?(
        payload: payload,
        delivery: @delivery
      )
        @delivery.update!(
          request_payload: payload,
          response_body: "blocked: private forum resource"
        )
        return ServiceResult.failure(error: "webhook_private_forum_resource")
      end

      url = @delivery.url.presence || SiteSetting.get("forum.event_webhook_url", "").to_s.strip
      return ServiceResult.failure(error: "webhook_url_missing") if url.blank?
      return ServiceResult.failure(error: "webhook_url_private") unless UrlSafety.public_http_url?(url)

      @delivery.update!(request_payload: payload)
      Community::DispatchForumEventWebhookJob.perform_later(
        url,
        payload,
        delivery_id: @delivery.id,
        attempt: 1
      )
      ServiceResult.success(queued: true)
    end
  end
end
