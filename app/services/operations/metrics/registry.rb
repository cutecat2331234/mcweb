# frozen_string_literal: true

module Operations
  module Metrics
    class Registry
      Entry = Data.define(:key, :type, :dimensions)

      KEY_PATTERN = /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+\z/
      LABEL_PATTERN = /\A[a-z][a-z0-9_]*\z/
      TYPES = %w[counter distribution gauge].freeze
      MAX_KEY_LENGTH = 100
      MAX_DIMENSIONS = 4
      MAX_LABEL_LENGTH = 48
      MAX_VALUES_PER_DIMENSION = 16
      MAX_CARDINALITY = 256
      MAX_TOTAL_CARDINALITY = 512
      FALLBACK_VALUE = "other"

      def initialize
        @entries = {}
        @cardinality = 0
        @frozen = false
      end

      def register(key:, type:, dimensions: {})
        raise FrozenError, "operations_metrics_registry_frozen" if frozen?

        normalized_key = normalize_key(key)
        normalized_type = normalize_type(type)
        normalized_dimensions = normalize_dimensions(dimensions)
        candidate = Entry.new(
          key: normalized_key,
          type: normalized_type,
          dimensions: normalized_dimensions
        )

        if (existing = @entries[normalized_key])
          return existing if existing == candidate

          raise ArgumentError, "operations_metric_definition_conflict"
        end

        candidate_cardinality = definition_cardinality(normalized_dimensions)
        if @cardinality + candidate_cardinality > MAX_TOTAL_CARDINALITY
          raise ArgumentError, "operations_metrics_registry_cardinality_too_high"
        end

        @entries[normalized_key] = candidate
        @cardinality += candidate_cardinality
        candidate
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

      def fetch(key)
        @entries.fetch(key.to_s)
      end

      def entries
        @entries.values
      end

      def keys
        @entries.keys
      end

      private

      def normalize_key(key)
        normalized = key.to_s.dup
        valid = normalized.length <= MAX_KEY_LENGTH &&
          normalized.match?(KEY_PATTERN)
        raise ArgumentError, "operations_metric_key_invalid" unless valid

        normalized.freeze
      end

      def normalize_type(type)
        normalized = type.to_s.dup
        unless TYPES.include?(normalized)
          raise ArgumentError, "operations_metric_type_invalid"
        end

        normalized.freeze
      end

      def normalize_dimensions(raw_dimensions)
        unless raw_dimensions.is_a?(Hash)
          raise TypeError, "operations_metric_dimensions_invalid"
        end
        if raw_dimensions.length > MAX_DIMENSIONS
          raise ArgumentError, "operations_metric_dimensions_too_many"
        end

        normalized = raw_dimensions.each_with_object({}) do |(raw_key, raw_values), result|
          key = normalize_label(raw_key, error: "operations_metric_dimension_key_invalid")
          if result.key?(key)
            raise ArgumentError, "operations_metric_dimension_duplicate"
          end
          unless raw_values.is_a?(Array)
            raise TypeError, "operations_metric_dimension_values_invalid"
          end

          values = raw_values.map do |raw_value|
            normalize_label(
              raw_value,
              error: "operations_metric_dimension_value_invalid"
            )
          end
          invalid_size = values.empty? ||
            values.length > MAX_VALUES_PER_DIMENSION
          if invalid_size
            raise ArgumentError, "operations_metric_dimension_values_invalid"
          end
          if values.uniq.length != values.length
            raise ArgumentError, "operations_metric_dimension_value_duplicate"
          end
          unless values.include?(FALLBACK_VALUE)
            raise ArgumentError, "operations_metric_dimension_fallback_required"
          end

          result[key] = values.sort.freeze
        end

        cardinality = definition_cardinality(normalized)
        if cardinality > MAX_CARDINALITY
          raise ArgumentError, "operations_metric_cardinality_too_high"
        end

        normalized.sort.to_h.freeze
      end

      def definition_cardinality(dimensions)
        dimensions.values.reduce(1) do |product, values|
          product * values.length
        end
      end

      def normalize_label(value, error:)
        normalized = value.to_s.dup
        valid = normalized.length <= MAX_LABEL_LENGTH &&
          normalized.match?(LABEL_PATTERN)
        raise ArgumentError, error unless valid

        normalized.freeze
      end
    end
  end
end
