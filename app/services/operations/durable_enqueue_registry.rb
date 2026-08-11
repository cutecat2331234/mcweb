# frozen_string_literal: true

module Operations
  class DurableEnqueueRegistry
    Entry = Data.define(
      :key,
      :source_kind,
      :queue_name,
      :replay_contract,
      :enqueue_stale_seconds,
      :lease_seconds,
      :heartbeat_seconds,
      :max_attempts,
      :retry_delays,
      :argument_schema,
      :executor
    )

    KEY_PATTERN = /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+\z/
    SOURCE_KIND_PATTERN = /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*\z/
    ARGUMENT_TYPES = %w[integer string boolean integer_list].freeze
    MAX_ARGUMENT_BYTES = 8.kilobytes
    MAX_STRING_LENGTH = 2_000
    REPLAY_CONTRACTS = %w[idempotent stable_idempotency_key at_least_once].freeze

    def initialize
      @entries = {}
      @frozen = false
    end

    def register(
      key:,
      source_kind:,
      queue:,
      replay_contract:,
      enqueue_stale_after: 1.minute,
      lease: 5.minutes,
      heartbeat: 1.minute,
      max_attempts: 5,
      retry_delays: [ 1.minute, 5.minutes, 30.minutes, 2.hours ],
      argument_schema: {},
      &executor
    )
      raise FrozenError, "durable_enqueue_registry_frozen" if frozen?

      normalized_key = key.to_s
      normalized_source_kind = source_kind.to_s
      normalized_queue = queue.to_s
      normalized_replay_contract = replay_contract.to_s
      raise ArgumentError, "durable_enqueue_key_invalid" unless normalized_key.match?(KEY_PATTERN)
      raise ArgumentError, "durable_enqueue_source_kind_invalid" unless normalized_source_kind.match?(SOURCE_KIND_PATTERN)
      raise ArgumentError, "durable_enqueue_queue_invalid" unless normalized_queue.in?(ApplicationJob::QUEUE_NAMES.values)
      unless normalized_replay_contract.in?(REPLAY_CONTRACTS)
        raise ArgumentError, "durable_enqueue_replay_contract_invalid"
      end
      raise ArgumentError, "durable_enqueue_handler_duplicate" if @entries.key?(normalized_key)
      raise ArgumentError, "durable_enqueue_executor_required" unless executor

      normalized_lease = Integer(lease.respond_to?(:to_i) ? lease.to_i : lease, exception: false)
      normalized_heartbeat = Integer(heartbeat.respond_to?(:to_i) ? heartbeat.to_i : heartbeat, exception: false)
      normalized_enqueue_stale = Integer(
        enqueue_stale_after.respond_to?(:to_i) ? enqueue_stale_after.to_i : enqueue_stale_after,
        exception: false
      )
      normalized_max_attempts = Integer(max_attempts, exception: false)
      unless normalized_enqueue_stale&.between?(30, 1.hour.to_i)
        raise ArgumentError, "durable_enqueue_stale_window_invalid"
      end
      raise ArgumentError, "durable_enqueue_lease_invalid" unless normalized_lease&.between?(30, 1.hour.to_i)
      unless normalized_heartbeat&.between?(5, normalized_lease / 2)
        raise ArgumentError, "durable_enqueue_heartbeat_invalid"
      end
      raise ArgumentError, "durable_enqueue_max_attempts_invalid" unless normalized_max_attempts&.between?(1, 10)

      normalized_retry_delays = Array(retry_delays).map { |value| Integer(value, exception: false) }
      if normalized_retry_delays.any?(&:nil?) || normalized_retry_delays.any? { |value| value < 1 }
        raise ArgumentError, "durable_enqueue_retry_delays_invalid"
      end
      normalized_retry_delays = normalized_retry_delays.first(normalized_max_attempts - 1).freeze

      entry = Entry.new(
        key: normalized_key.freeze,
        source_kind: normalized_source_kind.freeze,
        queue_name: normalized_queue.freeze,
        replay_contract: normalized_replay_contract.freeze,
        enqueue_stale_seconds: normalized_enqueue_stale,
        lease_seconds: normalized_lease,
        heartbeat_seconds: normalized_heartbeat,
        max_attempts: normalized_max_attempts,
        retry_delays: normalized_retry_delays,
        argument_schema: normalize_schema(argument_schema).freeze,
        executor:
      )
      @entries[normalized_key] = entry
      entry
    end

    def normalize_arguments(entry, raw_arguments)
      source = raw_arguments.to_h.deep_stringify_keys
      unknown = source.keys - entry.argument_schema.keys
      raise ArgumentError, "durable_enqueue_arguments_unsupported" if unknown.any?

      normalized = entry.argument_schema.each_with_object({}) do |(key, schema), result|
        value = source[key]
        if value.nil? || (value.respond_to?(:empty?) && value.empty?)
          raise ArgumentError, "durable_enqueue_argument_required" if schema[:required]
          next
        end

        result[key] = normalize_argument(value, schema)
      end
      if ActiveSupport::JSON.encode(normalized).bytesize > MAX_ARGUMENT_BYTES
        raise ArgumentError, "durable_enqueue_arguments_too_large"
      end
      normalized.freeze
    rescue NoMethodError, TypeError
      raise ArgumentError, "durable_enqueue_arguments_invalid"
    end

    def freeze!
      @entries.freeze
      @frozen = true
      self
    end

    def frozen?
      @frozen
    end

    def entry(key)
      @entries[key.to_s]
    end

    def entries
      @entries.values
    end

    private

    def normalize_schema(raw_schema)
      raw_schema.to_h.each_with_object({}) do |(raw_key, raw_definition), normalized|
        key = raw_key.to_s
        raise ArgumentError, "durable_enqueue_argument_key_invalid" unless key.match?(/\A[a-z][a-z0-9_]*\z/)

        definition = raw_definition.to_h.symbolize_keys.slice(
          :type,
          :required,
          :minimum,
          :maximum,
          :maximum_items,
          :pattern
        )
        type = definition.fetch(:type).to_s
        raise ArgumentError, "durable_enqueue_argument_type_invalid" unless type.in?(ARGUMENT_TYPES)

        pattern = definition[:pattern]
        if pattern && !pattern.is_a?(Regexp)
          raise ArgumentError, "durable_enqueue_argument_pattern_invalid"
        end
        maximum = Integer(definition[:maximum], exception: false)
        if type == "string" && !maximum&.between?(1, MAX_STRING_LENGTH)
          raise ArgumentError, "durable_enqueue_argument_maximum_invalid"
        end
        normalized[key] = {
          type:,
          required: ActiveModel::Type::Boolean.new.cast(definition[:required]),
          minimum: Integer(definition[:minimum], exception: false),
          maximum:,
          maximum_items: Integer(definition[:maximum_items], exception: false),
          pattern:
        }.compact.freeze
      end
    end

    def normalize_argument(value, schema)
      case schema.fetch(:type)
      when "integer"
        integer = Integer(value, exception: false)
        invalid = integer.nil?
        invalid ||= schema[:minimum] && integer < schema[:minimum]
        invalid ||= schema[:maximum] && integer > schema[:maximum]
        raise ArgumentError, "durable_enqueue_argument_invalid" if invalid

        integer
      when "string"
        string = value.to_s
        invalid = schema[:maximum] && string.length > schema[:maximum]
        invalid ||= schema[:pattern] && !string.match?(schema[:pattern])
        raise ArgumentError, "durable_enqueue_argument_invalid" if invalid

        string
      when "boolean"
        boolean = ActiveModel::Type::Boolean.new.cast(value)
        unless value.in?([ true, false, 0, 1, "0", "1", "true", "false" ])
          raise ArgumentError, "durable_enqueue_argument_invalid"
        end

        boolean
      when "integer_list"
        values = value.is_a?(Array) ? value : value.to_s.split(/[\s,]+/)
        parsed = values.reject { |item| item.to_s.blank? }
                       .map { |item| Integer(item, exception: false) }
        integers = parsed.compact.uniq
        invalid = integers.empty? || parsed.any?(&:nil?)
        invalid ||= schema[:minimum] && integers.any? { |item| item < schema[:minimum] }
        invalid ||= schema[:maximum_items] && integers.length > schema[:maximum_items]
        raise ArgumentError, "durable_enqueue_argument_invalid" if invalid

        integers
      end
    end
  end
end
