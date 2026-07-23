# frozen_string_literal: true

module Administration
  # Turns an in-process Mcweb::Events payload (which may contain ActiveRecord
  # objects) into a safe, JSON-friendly hash for outbound webhook delivery.
  # Only public fields are exposed.
  class SerializeEventPayload < ApplicationService
    def initialize(event:, payload:)
      @event = event.to_s
      @payload = payload || {}
    end

    def call
      {
        "event" => @event,
        "occurred_at" => Time.current.iso8601,
        "data" => @payload.each_with_object({}) do |(key, value), data|
          serialized = serialize_value(value)
          data[key.to_s] = serialized unless serialized.nil?
        end
      }
    end

    private

    def serialize_value(value)
      case value
      when Community::Topic then serialize_topic(value)
      when Community::Post then serialize_post(value)
      when ::User then serialize_user(value)
      when String, Numeric, TrueClass, FalseClass, NilClass then value
      when Hash then value.transform_keys(&:to_s)
      else value.respond_to?(:to_s) ? value.to_s : nil
      end
    end

    def serialize_topic(topic)
      {
        "id" => topic.public_id,
        "title" => topic.title,
        "section_id" => topic.section&.slug,
        "author_id" => topic.user&.public_id
      }
    end

    def serialize_post(post)
      {
        "id" => post.id,
        "topic_id" => post.topic&.public_id,
        "floor_number" => post.floor_number,
        "author_id" => post.user&.public_id
      }
    end

    def serialize_user(user)
      { "id" => user.public_id, "username" => user.username }
    end
  end
end
