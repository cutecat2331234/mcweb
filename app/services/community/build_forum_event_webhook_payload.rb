# frozen_string_literal: true

module Community
  class BuildForumEventWebhookPayload < ApplicationService
    def initialize(event_type:, topic:, post: nil, extra: {})
      @event_type = event_type.to_s
      @topic = topic
      @post = post
      @extra = extra || {}
    end

    def call
      payload = {
        event: @event_type,
        occurred_at: Time.current.iso8601,
        topic: topic_payload(@topic)
      }
      payload[:post] = post_payload(@post) if @post
      payload.merge!(@extra.symbolize_keys)
      ServiceResult.success(payload)
    end

  private

    def topic_payload(topic)
      {
        id: topic.public_id,
        title: topic.title,
        section_slug: topic.section.slug,
        section_name: topic.section.name,
        status: topic.status,
        path: Rails.application.routes.url_helpers.forum_topic_path(topic)
      }
    end

    def post_payload(post)
      {
        id: post.id,
        floor_number: post.floor_number,
        user_id: post.user_id,
        username: post.user.username,
        body_excerpt: post.body.to_s.truncate(200),
        path: "#{Rails.application.routes.url_helpers.forum_topic_path(post.topic)}#post-#{post.id}"
      }
    end
  end
end
