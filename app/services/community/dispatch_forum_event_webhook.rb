# frozen_string_literal: true

module Community
  class DispatchForumEventWebhook < ApplicationService
    EVENT_TYPES = Community::BuildForumEventWebhookPayload::EVENT_TYPES
    DEFAULT_EVENTS = EVENT_TYPES.join(",")

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

      # Central emission point for forum events: notify the in-process plugin event
      # bus regardless of whether an outbound webhook is configured, so extensions
      # always observe the event. Listener errors are isolated by Mcweb::Events.
      Mcweb::Events.publish("forum.#{@event_type}", topic: @topic, post: @post, **@extra)
      return ServiceResult.success(skipped: :event_disabled) unless self.class.enabled_events.include?(@event_type)
      unless Community::ForumEventWebhookPolicy.exportable?(
        event_type: @event_type,
        topic: @topic,
        post: @post
      )
        return ServiceResult.success(skipped: :private_forum_resource)
      end

      url = SiteSetting.get("forum.event_webhook_url", "").to_s.strip
      return ServiceResult.success(skipped: :url_missing) if url.blank?
      return ServiceResult.success(skipped: :url_private) unless UrlSafety.public_http_url?(url)

      payload_result = Community::BuildForumEventWebhookPayload.call(
        event_type: @event_type,
        topic: @topic,
        post: @post,
        extra: @extra
      )
      return payload_result if payload_result.failure?

      payload = payload_result.value
      Community::DispatchForumEventWebhookJob.perform_later(url, payload)
      ServiceResult.success(queued: true)
    end
  end
end
