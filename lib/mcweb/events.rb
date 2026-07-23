# frozen_string_literal: true

module Mcweb
  # Lightweight, error-isolated domain event bus for the McWeb plugin ecosystem.
  #
  # This is a thin facade over ActiveSupport::Notifications (we deliberately do not
  # reinvent a pub/sub engine). Domain events are published under the "<event>.mcweb"
  # namespace so they never collide with Rails' own instrumentation. Extensions and
  # plugins subscribe to react to core actions WITHOUT modifying core code — the same
  # idea as XenForo "code event listeners".
  #
  #   Mcweb::Events.subscribe("forum.post.created") do |payload|
  #     payload[:post]  # => Community::Post
  #     payload[:topic] # => Community::Topic
  #   end
  #
  #   Mcweb::Events.publish("forum.post.created", post: post, topic: topic)
  #
  # Listener errors are rescued and logged so a misbehaving plugin can never break
  # the core request flow (mirrors the notify!/broadcast rescue pattern used
  # elsewhere in the app). Listeners run synchronously, after the triggering
  # database transaction has committed (events are emitted from post-commit
  # side-effect paths), so it is safe to read persisted records inside a listener.
  module Events
    SUFFIX = "mcweb"

    # Canonical catalog of core domain events plugins can rely on. Publishing an
    # event outside this list still works (forward compatibility), but documented
    # events are treated as a stable extension API.
    CATALOG = %w[
      forum.topic.created
      forum.post.created
      forum.post.edited
      forum.post.deleted
      forum.post.restored
      forum.post.rejected
      forum.post.approved
      forum.topic.solved
      forum.topic.moved
      forum.reaction.added
      forum.reaction.removed
      identity.user.registered
    ].freeze

    class << self
      # Publish a domain event. Returns true. Never raises due to listener errors.
      def publish(event, payload = {})
        ActiveSupport::Notifications.instrument(full_name(event), payload)
        true
      end

      # Subscribe a listener to an event. The block receives the payload hash.
      # Returns a subscriber handle that can be passed to .unsubscribe.
      def subscribe(event, &block)
        raise ArgumentError, "a listener block is required" unless block

        ActiveSupport::Notifications.subscribe(full_name(event)) do |notification|
          invoke_listener(event, block, notification.payload)
        end
      end

      def unsubscribe(subscriber)
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      # Fully-qualified, namespaced event name used on the underlying bus.
      def full_name(event)
        name = event.to_s
        name.end_with?(".#{SUFFIX}") ? name : "#{name}.#{SUFFIX}"
      end

      private

      def invoke_listener(event, block, payload)
        block.call(payload)
      rescue StandardError => e
        message = "[mcweb.events] listener for #{event} raised #{e.class}: #{e.message}"
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.error(message)
        else
          warn(message)
        end
        nil
      end
    end
  end
end
