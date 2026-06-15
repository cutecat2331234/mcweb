# frozen_string_literal: true

module Community
  class DispatchTestSavedSearchWebhook < ApplicationService
    def call
      url = SiteSetting.get("forum.saved_search_webhook_url", "").to_s.strip
      return ServiceResult.failure(error: "未配置 Webhook URL") if url.blank?

      payload = {
        event: "saved_search.match",
        search_id: 0,
        search_name: "Webhook 测试",
        query: "test",
        filters: {},
        occurred_at: Time.current.iso8601,
        test: true,
        topics: [
          {
            id: "test_topic",
            title: "测试主题",
            path: "/forum/search?q=test"
          }
        ]
      }

      secret = SiteSetting.get("forum.saved_search_webhook_secret", "").to_s.strip.presence
      Community::DispatchSavedSearchWebhookJob.perform_later(nil, url, payload, secret: secret)
      ServiceResult.success(queued: true)
    end
  end
end
