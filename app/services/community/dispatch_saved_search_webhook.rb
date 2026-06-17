# frozen_string_literal: true

module Community
  class DispatchSavedSearchWebhook < ApplicationService
    def initialize(saved_search:, topics:)
      @saved_search = saved_search
      @topics = topics
    end

    def call
      url = @saved_search.webhook_url.to_s.strip
      return ServiceResult.success(skipped: true) if url.blank?

      payload = {
        event: "saved_search.match",
        search_id: @saved_search.id,
        search_name: @saved_search.name,
        query: @saved_search.query,
        filters: @saved_search.filters,
        occurred_at: Time.current.iso8601,
        topics: @topics.map do |topic|
          {
            id: topic.public_id,
            title: topic.title,
            path: Rails.application.routes.url_helpers.forum_topic_path(topic)
          }
        end
      }

      secret = SiteSetting.get("forum.saved_search_webhook_secret", "").to_s.strip.presence
      Community::DispatchSavedSearchWebhookJob.perform_later(@saved_search.id, url, payload, secret: secret)
      ServiceResult.success(queued: true)
    end
  end
end
