# frozen_string_literal: true

module Community
  class DispatchForumEventWebhook < ApplicationService
    EVENT_TYPES = %w[topic.created post.created post.edited post.deleted post.restored post.rejected post.approved topic.solved topic.moved].freeze
    DEFAULT_EVENTS = "topic.created,post.created,post.edited,post.deleted,post.restored,post.rejected,post.approved,topic.solved,topic.moved"

    def self.enabled_events
      raw = SiteSetting.get("forum.event_webhook_events", DEFAULT_EVENTS).to_s
      raw.split(/[,\s]+/).map(&:strip).reject(&:blank?) & EVENT_TYPES
    end

    def initialize(event_type:, topic:, post: nil, extra: {})
      @event_type = event_type.to_s
      @topic = topic
      @post = post
      @extra = extra || {}
    end

    def call
      return ServiceResult.success(skipped: :unsupported_event) unless EVENT_TYPES.include?(@event_type)
      return ServiceResult.success(skipped: :event_disabled) unless self.class.enabled_events.include?(@event_type)

      url = SiteSetting.get("forum.event_webhook_url", "").to_s.strip
      return ServiceResult.success(skipped: :url_missing) if url.blank?
      return ServiceResult.success(skipped: :url_private) unless UrlSafety.public_http_url?(url)

      payload_result = Community::BuildForumEventWebhookPayload.call(
        event_type: @event_type,
        topic: @topic,
        post: @post,
        extra: @extra
      )
      payload = payload_result.value
      secret = SiteSetting.get("forum.event_webhook_secret", "").to_s.strip.presence
      Community::DispatchForumEventWebhookJob.perform_later(url, payload, secret)
      ServiceResult.success(queued: true)
    end
  end
end
