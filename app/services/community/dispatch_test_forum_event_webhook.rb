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
      secret = SiteSetting.get("forum.event_webhook_secret", "").to_s.strip.presence
      Community::DispatchForumEventWebhookJob.perform_later(url, payload, secret)
      ServiceResult.success(queued: true, event_type: @event_type)
    end

  private

    def build_payload
      {
        event: @event_type,
        occurred_at: Time.current.iso8601,
        test: true,
        topic: {
          id: "test_topic",
          title: I18n.t("mcweb.forum.webhook_test.event_topic_title"),
          section_slug: "general",
          section_name: I18n.t("mcweb.forum.webhook_test.section_name"),
          status: "published",
          path: "#{Mcweb::Paths::APP_PREFIX}/forum/latest"
        },
        post: {
          id: 0,
          floor_number: 1,
          user_id: nil,
          username: "test_user",
          body_excerpt: I18n.t("mcweb.forum.webhook_test.body_excerpt"),
          path: "#{Mcweb::Paths::APP_PREFIX}/forum/latest#post-0"
        }
      }
    end
  end
end
