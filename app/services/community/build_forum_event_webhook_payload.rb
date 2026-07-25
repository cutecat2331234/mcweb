# frozen_string_literal: true

module Community
  class BuildForumEventWebhookPayload < ApplicationService
    EVENT_TYPES = %w[
      topic.created
      post.created
      post.edited
      post.deleted
      post.restored
      post.rejected
      post.approved
      topic.solved
      topic.moved
    ].freeze
    IDENTIFIER_PATTERN = /\A[A-Za-z0-9_-]{1,128}\z/

    def initialize(event_type:, topic:, post: nil, extra: {})
      @event_type = event_type.to_s
      @topic = topic
      @post = post
      # Kept in the initializer for source compatibility. Arbitrary caller data
      # is intentionally not serialized across the outbound webhook boundary.
      @extra = extra || {}
    end

    def call
      return ServiceResult.failure(error: "webhook_event_unsupported") unless EVENT_TYPES.include?(@event_type)

      payload = {
        event: @event_type,
        occurred_at: Time.current.iso8601(3)
      }
      topic = topic_payload(@topic)
      payload[:topic] = topic if topic
      payload[:post] = post_payload(@post) if @post
      ServiceResult.success(payload)
    end

    class << self
      # Rebuild a queued or persisted payload from a strict allowlist. This is
      # deliberately repeated at the job/model boundaries so legacy rich
      # payloads cannot be retried or saved verbatim.
      def sanitize(payload, event_type: nil, topic_id: nil, post_id: nil, occurred_at: nil, test: nil)
        input = payload.respond_to?(:to_h) ? payload.to_h.deep_stringify_keys : {}
        event = normalize_event(event_type.presence || input["event"])
        return {} unless event

        safe = {
          "event" => event,
          "occurred_at" => normalize_time(occurred_at || input["occurred_at"])
        }

        safe_topic_id = normalize_identifier(topic_id || input.dig("topic", "id") || input["topic_id"])
        safe_post_id = normalize_identifier(post_id || input.dig("post", "id") || input["post_id"])
        safe["topic"] = { "id" => safe_topic_id } if safe_topic_id
        safe["post"] = { "id" => safe_post_id } if safe_post_id
        safe["test"] = true if test == true || input["test"] == true
        safe
      end

      def normalize_identifier(value)
        return value if value.is_a?(Integer) && value.positive?

        identifier = value.to_s
        identifier if IDENTIFIER_PATTERN.match?(identifier)
      end

      private

      def normalize_event(value)
        event = value.to_s.delete_prefix("forum.")
        event if EVENT_TYPES.include?(event)
      end

      def normalize_time(value)
        time = value.respond_to?(:iso8601) ? value : Time.zone.parse(value.to_s)
        (time || Time.current).iso8601(3)
      rescue ArgumentError, TypeError
        Time.current.iso8601(3)
      end
    end

  private

    def topic_payload(topic)
      identifier = self.class.normalize_identifier(topic&.public_id)
      { id: identifier } if identifier
    end

    def post_payload(post)
      identifier = self.class.normalize_identifier(post&.id)
      { id: identifier } if identifier
    end
  end
end
