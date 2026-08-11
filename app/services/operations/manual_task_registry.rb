# frozen_string_literal: true

module Operations
  class ManualTaskRegistry
    Entry = Data.define(
      :key,
      :label_key,
      :description_key,
      :permissions,
      :argument_schema,
      :executor
    )

    KEY_PATTERN = /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+\z/
    ARGUMENT_TYPES = %w[integer integer_list string uuid_list].freeze
    MAX_ARGUMENT_BYTES = 8.kilobytes
    MAX_STRING_LENGTH = 2_000

    def initialize
      @entries = {}
      @frozen = false
    end

    def register(key:, label_key:, description_key:, permissions:, argument_schema: {}, &executor)
      raise FrozenError, "manual_task_registry_frozen" if frozen?

      normalized_key = key.to_s
      raise ArgumentError, "manual_task_key_invalid" unless normalized_key.match?(KEY_PATTERN)
      raise ArgumentError, "manual_task_duplicate" if @entries.key?(normalized_key)
      raise ArgumentError, "manual_task_executor_required" unless executor

      normalized_permissions = Array(permissions).map(&:to_s).reject(&:blank?).uniq.freeze
      raise ArgumentError, "manual_task_permissions_required" if normalized_permissions.empty?

      entry = Entry.new(
        key: normalized_key.freeze,
        label_key: label_key.to_s.freeze,
        description_key: description_key.to_s.freeze,
        permissions: normalized_permissions,
        argument_schema: normalize_schema(argument_schema).freeze,
        executor: executor
      )
      @entries[normalized_key] = entry
      entry
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
        raise ArgumentError, "manual_task_argument_key_invalid" unless key.match?(/\A[a-z][a-z0-9_]*\z/)

        definition = raw_definition.to_h.symbolize_keys.slice(
          :type,
          :required,
          :minimum,
          :maximum,
          :maximum_items,
          :label_key,
          :help_key
        )
        type = definition.fetch(:type).to_s
        raise ArgumentError, "manual_task_argument_type_invalid" unless type.in?(ARGUMENT_TYPES)

        maximum = Integer(definition[:maximum], exception: false)
        if type == "string" && !maximum&.between?(1, MAX_STRING_LENGTH)
          raise ArgumentError, "manual_task_argument_maximum_invalid"
        end

        normalized[key] = {
          type: type,
          required: ActiveModel::Type::Boolean.new.cast(definition[:required]),
          minimum: Integer(definition[:minimum], exception: false),
          maximum:,
          maximum_items: Integer(definition[:maximum_items], exception: false),
          label_key: definition[:label_key].to_s.presence,
          help_key: definition[:help_key].to_s.presence
        }.compact.freeze
      end
    end
  end
end
