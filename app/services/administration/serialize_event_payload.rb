# frozen_string_literal: true

module Administration
  # Turns an in-process Mcweb::Events payload (which may contain ActiveRecord
  # objects) into an identifier-only invalidation for outbound delivery. Rich
  # objects remain available to trusted in-process plugins. Commerce events use
  # a fixed status/amount/identifier allow-list; titles, bodies, usernames,
  # reasons, IP addresses, provider metadata, and arbitrary hashes never leave
  # McWeb.
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
    COMMERCE_FIELDS = {
      "order" => %w[public_id status total_cents currency],
      "payment" => %w[id status amount_cents currency],
      "refund" => %w[id status amount_cents currency],
      "inventory" => %w[
        target_type target_id product_public_id variant_id
        available_quantity reserved_quantity sold_quantity
      ],
      "movement" => %w[
        public_id type quantity available_delta reserved_delta sold_delta
      ],
      "fulfillment" => %w[
        id delivery_id order_item_id status attempts_count max_attempts
        retryable next_attempt_at fulfilled_at cancelled_at
      ],
      "attempt" => %w[number trigger status],
      "result" => %w[success status error_code simulated external_reference]
    }.freeze

    def initialize(event:, payload:)
      @event = event.to_s
      @payload = payload || {}
    end

    def call
      {
        "event" => @event,
        "occurred_at" => Time.current.iso8601(3),
        "data" => serialized_data
      }
    end

    class << self
      # Defense in depth for jobs invoked with an already serialized envelope.
      def sanitize_envelope(payload)
        input = payload.respond_to?(:to_h) ? payload.to_h.deep_stringify_keys : {}
        event = input["event"].to_s
        return {} unless Mcweb::Events::CATALOG.include?(event)

        raw_data = input.fetch("data", {}).to_h
        data = if event.start_with?("commerce.")
          sanitize_commerce_data(raw_data)
        else
          raw_data.each_with_object({}) do |(key, value), safe|
            next unless RECORD_KEYS.include?(key)

            identifiers = sanitize_identifier_hash(value)
            safe[key] = identifiers if identifiers.present?
          end
        end

        {
          "event" => event,
          "occurred_at" => normalize_time(input["occurred_at"]),
          "data" => data
        }
      rescue NoMethodError, TypeError
        {}
      end

      def sanitize_commerce_data(payload)
        values = payload.respond_to?(:to_h) ? payload.to_h.deep_stringify_keys : {}
        COMMERCE_FIELDS.each_with_object({}) do |(section, fields), safe|
          section_value = values[section]
          next unless section_value.respond_to?(:to_h)

          filtered = section_value.to_h.deep_stringify_keys.slice(*fields)
            .each_with_object({}) do |(key, value), entries|
              scalar = sanitize_commerce_scalar(value)
              entries[key] = scalar unless scalar.nil?
            end
          safe[section] = filtered if filtered.present?
        end
      end

      private

      def sanitize_commerce_scalar(value)
        case value
        when true, false, Numeric
          value
        when Time, Date, DateTime
          value.iso8601
        when String
          value.first(200)
        end
      end

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

    def serialized_data
      if @event.start_with?("commerce.")
        self.class.sanitize_commerce_data(@payload)
      else
        @payload.each_with_object({}) do |(key, value), data|
          next unless RECORD_KEYS.include?(key.to_s)

          serialized = serialize_value(value)
          data[key.to_s] = serialized unless serialized.nil?
        end
      end
    end

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
