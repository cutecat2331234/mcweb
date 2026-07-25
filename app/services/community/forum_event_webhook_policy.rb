# frozen_string_literal: true

module Community
  # Privacy boundary for outbound forum webhooks.
  #
  # Plugins receive the rich in-process event objects, but outbound integrations
  # are unauthenticated readers. They may only receive invalidations for content
  # that an anonymous visitor can list. Staff whispers and moderation-only posts
  # never cross this boundary.
  module ForumEventWebhookPolicy
    module_function

    POST_EVENTS = %w[
      post.created
      post.edited
      post.deleted
      post.restored
      post.rejected
      post.approved
      topic.solved
    ].freeze
    PUBLIC_POST_STATES = %w[post.created post.edited post.restored post.approved topic.solved].freeze

    def exportable?(event_type:, topic:, post: nil)
      event = event_type.to_s.delete_prefix("forum.")
      return false unless Community::BuildForumEventWebhookPayload::EVENT_TYPES.include?(event)
      return false unless public_topic?(topic)
      return true unless POST_EVENTS.include?(event)
      return false unless public_post_identity?(post, topic)
      return false if event == "post.rejected"
      return post.status == "published" if event == "post.deleted"

      PUBLIC_POST_STATES.include?(event) &&
        post.status == "published" &&
        post.deleted_at.nil?
    rescue StandardError
      false
    end

    # Rebuild current resources from an identifier-only queued payload. This is
    # intentionally called immediately before delivery: a topic can be moved to
    # a private section, or a post can become a whisper/rejected item, after the
    # event was originally enqueued.
    def exportable_payload?(payload:, delivery: nil)
      values = payload.respond_to?(:to_h) ? payload.to_h.with_indifferent_access : {}
      event = values[:event].to_s.delete_prefix("forum.")
      return false unless Community::BuildForumEventWebhookPayload::EVENT_TYPES.include?(event)
      return valid_test_payload?(values, event) if values[:test] == true

      topic_identifier = delivery&.topic&.public_id ||
        values.dig(:topic, :id) ||
        values[:topic_id]
      post_identifier = delivery&.forum_post_id ||
        values.dig(:post, :id) ||
        values[:post_id]
      topic = find_topic(topic_identifier)
      post = find_post(post_identifier)
      topic ||= post&.topic
      return false if post && topic && post.forum_topic_id != topic.id

      exportable?(event_type: event, topic: topic, post: post)
    rescue StandardError
      false
    end

    # The generic event-subscription bridge shares the same anonymous boundary.
    # Non-forum events are still allowed, but their serializer only emits record
    # identifiers.
    def exportable_bus_event?(event:, payload:)
      event_name = event.to_s
      return true unless event_name.start_with?("forum.")

      values = payload.respond_to?(:to_h) ? payload.to_h.with_indifferent_access : {}
      post = values[:post]
      topic = values[:topic] || (post.topic if post.is_a?(Community::Post))

      case event_name
      when /\Aforum\.post\./
        exportable?(
          event_type: event_name.delete_prefix("forum."),
          topic: topic,
          post: post
        )
      when /\Aforum\.reaction\./
        public_topic?(topic) && public_post_identity?(post, topic) &&
          post.status == "published" && post.deleted_at.nil?
      when "forum.topic.fields.updated"
        public_topic?(topic)
      when /\Aforum\.topic\./
        exportable?(
          event_type: event_name.delete_prefix("forum."),
          topic: topic,
          post: post
        )
      when "forum.report.created", "forum.warning.issued"
        false
      else
        false
      end
    rescue StandardError
      false
    end

    # Equivalent execution-time guard for the generic subscription queue. The
    # envelope has already been reduced to stable identifiers, so it is safe to
    # resolve those identifiers and apply the same anonymous-reader boundary.
    def exportable_envelope?(payload)
      values = payload.respond_to?(:to_h) ? payload.to_h.with_indifferent_access : {}
      event_name = values[:event].to_s
      return false unless Mcweb::Events::CATALOG.include?(event_name)
      return true unless event_name.start_with?("forum.")

      data = values[:data]
      return false unless data.respond_to?(:to_h)

      records = data.to_h.with_indifferent_access
      post = find_post(records.dig(:post, :id))
      topic = find_topic(
        records.dig(:topic, :id) ||
          records.dig(:post, :topic_id)
      )
      topic ||= post&.topic
      return false if post && topic && post.forum_topic_id != topic.id

      case event_name
      when /\Aforum\.post\./
        exportable?(
          event_type: event_name.delete_prefix("forum."),
          topic: topic,
          post: post
        )
      when /\Aforum\.reaction\./
        public_topic?(topic) &&
          public_post_identity?(post, topic) &&
          post.status == "published" &&
          post.deleted_at.nil?
      when "forum.topic.fields.updated"
        public_topic?(topic)
      when /\Aforum\.topic\./
        exportable?(
          event_type: event_name.delete_prefix("forum."),
          topic: topic,
          post: post
        )
      when "forum.report.created", "forum.warning.issued"
        false
      else
        false
      end
    rescue StandardError
      false
    end

    def public_topic?(topic)
      topic.is_a?(Community::Topic) &&
        topic.persisted? &&
        Community::ForumAccess.listed_topic_visible?(topic: topic, user: nil)
    end
    private_class_method :public_topic?

    def public_post_identity?(post, topic)
      post.is_a?(Community::Post) &&
        post.persisted? &&
        post.forum_topic_id == topic&.id &&
        !post.whisper? &&
        post.post_type == "regular"
    end
    private_class_method :public_post_identity?

    def find_topic(identifier)
      value = Community::BuildForumEventWebhookPayload.normalize_identifier(identifier)
      return unless value

      Community::Topic.with_discarded.find_by(public_id: value.to_s)
    end
    private_class_method :find_topic

    def find_post(identifier)
      id = Integer(identifier, exception: false)
      return unless id&.positive?

      Community::Post.with_discarded.find_by(id: id)
    end
    private_class_method :find_post

    def valid_test_payload?(values, event)
      topic_id = values.dig(:topic, :id) || values[:topic_id]
      post_id = values.dig(:post, :id) || values[:post_id]
      needs_post = POST_EVENTS.include?(event)

      topic_id.to_s == "test_topic" &&
        (needs_post ? post_id.to_s == "test_post" : post_id.blank?)
    end
    private_class_method :valid_test_payload?
  end
end
