# frozen_string_literal: true

module Community
  class DispatchTestForumEventWebhook < ApplicationService
    def initialize(event_type: "topic.created")
      @event_type = event_type.to_s
    end

    def call
      return ServiceResult.failure(error: "webhook_event_unsupported") unless DispatchForumEventWebhook::EVENT_TYPES.include?(@event_type)

      url = SiteSetting.get("forum.event_webhook_url", "").to_s.strip
      return ServiceResult.failure(error: "webhook_url_missing") if url.blank?
      return ServiceResult.failure(error: "webhook_url_private") unless UrlSafety.public_http_url?(url)

      payload = build_payload
      Community::DispatchForumEventWebhookJob.perform_later(url, payload)
      ServiceResult.success(queued: true, event_type: @event_type)
    end

  private

    def build_payload
      {
        event: @event_type,
        occurred_at: Time.current.iso8601(3),
        test: true,
        topic: { id: "test_topic" }
      }.tap do |payload|
        payload[:post] = { id: "test_post" } if @event_type.start_with?("post.") || @event_type == "topic.solved"
      end
    end
  end
end
