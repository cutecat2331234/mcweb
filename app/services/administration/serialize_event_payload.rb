# frozen_string_literal: true

module Administration
  # Turns an in-process Mcweb::Events payload (which may contain ActiveRecord
  # objects) into an identifier-only invalidation for outbound delivery. Rich
  # objects remain available to trusted in-process plugins, but titles, bodies,
  # usernames, reasons, IP addresses, and arbitrary hashes never leave McWeb.
  class SerializeEventPayload < ApplicationService
    RECORD_KEYS = %w[
      actor
      post
      report
      reportable
      reporter
      topic
      user
      warning
    ].freeze
    IDENTIFIER_FIELDS = %w[id topic_id].freeze

    def initialize(event:, payload:)
      @event = event.to_s
      @payload = payload || {}
    end

    def call
      {
        "event" => @event,
        "occurred_at" => Time.current.iso8601(3),
        "data" => @payload.each_with_object({}) do |(key, value), data|
          next unless RECORD_KEYS.include?(key.to_s)

          serialized = serialize_value(value)
          data[key.to_s] = serialized unless serialized.nil?
        end
      }
    end

    class << self
      # Defense in depth for jobs invoked with an already serialized envelope.
      def sanitize_envelope(payload)
        input = payload.respond_to?(:to_h) ? payload.to_h.deep_stringify_keys : {}
        event = input["event"].to_s
        return {} unless Mcweb::Events::CATALOG.include?(event)

        data = input.fetch("data", {}).to_h.each_with_object({}) do |(key, value), safe|
          next unless RECORD_KEYS.include?(key)

          identifiers = sanitize_identifier_hash(value)
          safe[key] = identifiers if identifiers.present?
        end

        {
          "event" => event,
          "occurred_at" => normalize_time(input["occurred_at"]),
          "data" => data
        }
      rescue NoMethodError, TypeError
        {}
      end

      private

      def sanitize_identifier_hash(value)
        return {} unless value.respond_to?(:to_h)

        value.to_h.deep_stringify_keys.slice(*IDENTIFIER_FIELDS).each_with_object({}) do |(key, identifier), safe|
          normalized = Community::BuildForumEventWebhookPayload.normalize_identifier(identifier)
          safe[key] = normalized if normalized
        end
      end

      def normalize_time(value)
        time = value.respond_to?(:iso8601) ? value : Time.zone.parse(value.to_s)
        (time || Time.current).iso8601(3)
      rescue ArgumentError, TypeError
        Time.current.iso8601(3)
      end
    end

    private

    def serialize_value(value)
      case value
      when Community::Topic then identifiers(id: value.public_id)
      when Community::Post then identifiers(id: value.id, topic_id: value.topic&.public_id)
      when ::User then identifiers(id: value.public_id)
      when ActiveRecord::Base then serialize_generic_record(value)
      end
    end

    def serialize_generic_record(record)
      public_id = record.public_id if record.respond_to?(:public_id)
      identifiers(id: public_id.presence || record.id)
    end

    def identifiers(**values)
      values.each_with_object({}) do |(key, value), safe|
        identifier = Community::BuildForumEventWebhookPayload.normalize_identifier(value)
        safe[key.to_s] = identifier if identifier
      end.presence
    end
  end
end
