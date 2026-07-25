# frozen_string_literal: true

require "json"
require "time"

class SanitizeForumEventWebhookPayloads < ActiveRecord::Migration[8.0]
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

  def up
    return unless table_exists?(:forum_event_webhook_deliveries)

    rows = connection.select_all(<<~SQL.squish)
      SELECT deliveries.id,
             deliveries.event_type,
             deliveries.forum_post_id,
             deliveries.request_payload,
             deliveries.created_at,
             topics.public_id AS topic_public_id
      FROM forum_event_webhook_deliveries deliveries
      LEFT JOIN forum_topics topics
        ON topics.id = deliveries.forum_topic_id
    SQL

    rows.each do |row|
      payload = sanitize_payload(row)
      quoted_payload = connection.quote(payload.to_json)
      execute <<~SQL.squish
        UPDATE forum_event_webhook_deliveries
        SET request_payload = #{quoted_payload}::jsonb
        WHERE id = #{connection.quote(row["id"])}
      SQL
    end
  end

  def down
    # Removed content cannot and should not be reconstructed.
  end

  private

  def sanitize_payload(row)
    event = row["event_type"].to_s
    return {} unless EVENT_TYPES.include?(event)

    old_payload = parse_payload(row["request_payload"])
    safe = {
      "event" => event,
      "occurred_at" => normalize_time(old_payload["occurred_at"], row["created_at"])
    }

    topic_id = sanitize_identifier(row["topic_public_id"] || old_payload.dig("topic", "id"))
    post_id = sanitize_identifier(row["forum_post_id"] || old_payload.dig("post", "id"))
    safe["topic"] = { "id" => topic_id } if topic_id
    safe["post"] = { "id" => post_id } if post_id
    safe["test"] = true if old_payload["test"] == true
    safe
  end

  def parse_payload(value)
    return value.deep_stringify_keys if value.respond_to?(:deep_stringify_keys)

    JSON.parse(value.to_s)
  rescue JSON::ParserError, TypeError
    {}
  end

  def normalize_time(value, fallback)
    time = Time.iso8601(value.to_s)
    time.iso8601(3)
  rescue ArgumentError
    fallback.to_time.utc.iso8601(3)
  end

  def sanitize_identifier(value)
    return value if value.is_a?(Integer) && value.positive?

    identifier = value.to_s
    identifier if IDENTIFIER_PATTERN.match?(identifier)
  end
end
