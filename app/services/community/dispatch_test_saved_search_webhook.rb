# frozen_string_literal: true

module Community
  class DispatchTestSavedSearchWebhook < ApplicationService
    def initialize(saved_search: nil)
      @saved_search = saved_search
    end

    def call
      url = webhook_url
      return ServiceResult.failure(error: "webhook_url_missing") if url.blank?
      return ServiceResult.failure(error: "webhook_url_private") unless UrlSafety.public_http_url?(url)

      payload = build_payload
      secret = SiteSetting.get("forum.saved_search_webhook_secret", "").to_s.strip.presence
      search_id = @saved_search&.id
      Community::DispatchSavedSearchWebhookJob.perform_later(search_id, url, payload, secret: secret)
      ServiceResult.success(queued: true, saved_search_id: search_id)
    end

  private

    def webhook_url
      if @saved_search&.webhook_url.present?
        @saved_search.webhook_url.to_s.strip
      else
        SiteSetting.get("forum.saved_search_webhook_url", "").to_s.strip
      end
    end

    def build_payload
      if @saved_search
        topics = Community::SavedSearchMatcher.new(@saved_search).matching_topics.limit(5).to_a
        {
          event: "saved_search.match",
          search_id: @saved_search.id,
          search_name: @saved_search.name,
          query: @saved_search.query,
          filters: @saved_search.filters,
          occurred_at: Time.current.iso8601,
          test: true,
          topics: topics.map { |topic| topic_payload(topic) }
        }
      else
        {
          event: "saved_search.match",
          search_id: 0,
          search_name: I18n.t("mcweb.forum.webhook_test.search_name"),
          query: "test",
          filters: {},
          occurred_at: Time.current.iso8601,
          test: true,
          topics: [
            {
              id: "test_topic",
              title: I18n.t("mcweb.forum.webhook_test.topic_title"),
              path: "#{Mcweb::Paths::APP_PREFIX}/forum/search?q=test"
            }
          ]
        }
      end
    end

    def topic_payload(topic)
      {
        id: topic.public_id,
        title: topic.title,
        path: Rails.application.routes.url_helpers.forum_topic_path(topic)
      }
    end
  end
end
