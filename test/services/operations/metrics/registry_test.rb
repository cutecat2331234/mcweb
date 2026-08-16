# frozen_string_literal: true

require "test_helper"

module Operations
  module Metrics
    class RegistryTest < ActiveSupport::TestCase
      test "registers a typed low-cardinality definition and freezes it" do
        registry = Registry.new
        key = +"downstream.maintenance.run"
        dimension_key = +"outcome"
        dimension_value = +"success"

        entry = registry.register(
          key:,
          type: :counter,
          dimensions: {
            dimension_key => [ "other", dimension_value, "failure" ],
            mode: %w[other ranked unranked]
          }
        )
        registry.freeze!
        key.replace("mutated.metric")
        dimension_key.replace("mutated_dimension")
        dimension_value.replace("mutated_value")

        assert_equal "downstream.maintenance.run", entry.key
        assert_equal "counter", entry.type
        assert_equal %w[failure other success],
          entry.dimensions.fetch("outcome")
        assert_predicate registry, :frozen?
        assert_predicate entry, :frozen?
        assert_predicate entry.dimensions, :frozen?
        assert_predicate entry.dimensions.fetch("mode"), :frozen?
        assert entry.dimensions.values.flatten.all?(&:frozen?)
        assert_raises(FrozenError) do
          registry.register(
            key: "downstream.maintenance.late",
            type: :counter
          )
        end
      end

      test "equivalent duplicate definitions are idempotent" do
        registry = Registry.new
        first = registry.register(
          key: "downstream.queue.depth",
          type: "gauge",
          dimensions: { mode: %w[ranked other] }
        )
        duplicate = registry.register(
          key: "downstream.queue.depth",
          type: :gauge,
          dimensions: { "mode" => %w[other ranked] }
        )

        assert_same first, duplicate
        assert_equal 1, registry.entries.length
      end

      test "conflicting duplicate definitions fail closed" do
        registry = Registry.new
        registry.register(
          key: "downstream.queue.depth",
          type: :gauge,
          dimensions: { mode: %w[other ranked] }
        )

        type_error = assert_raises(ArgumentError) do
          registry.register(
            key: "downstream.queue.depth",
            type: :counter,
            dimensions: { mode: %w[other ranked] }
          )
        end
        dimension_error = assert_raises(ArgumentError) do
          registry.register(
            key: "downstream.queue.depth",
            type: :gauge,
            dimensions: { mode: %w[other ranked unranked] }
          )
        end

        assert_equal "operations_metric_definition_conflict", type_error.message
        assert_equal "operations_metric_definition_conflict",
          dimension_error.message
      end

      test "rejects invalid keys types and label definitions" do
        invalid_key = assert_raises(ArgumentError) do
          Registry.new.register(key: "dynamic user metric", type: :counter)
        end
        invalid_type = assert_raises(ArgumentError) do
          Registry.new.register(key: "downstream.valid", type: :histogram)
        end
        missing_fallback = assert_raises(ArgumentError) do
          Registry.new.register(
            key: "downstream.valid",
            type: :counter,
            dimensions: { outcome: %w[success failure] }
          )
        end
        dynamic_label = assert_raises(ArgumentError) do
          Registry.new.register(
            key: "downstream.valid",
            type: :counter,
            dimensions: { account_id: [ "other", "user-42@example.com" ] }
          )
        end

        assert_equal "operations_metric_key_invalid", invalid_key.message
        assert_equal "operations_metric_type_invalid", invalid_type.message
        assert_equal "operations_metric_dimension_fallback_required",
          missing_fallback.message
        assert_equal "operations_metric_dimension_value_invalid",
          dynamic_label.message
      end

      test "rejects definitions above the cardinality budget" do
        values = [ "other", *15.times.map { |index| "value_#{index}" } ]

        error = assert_raises(ArgumentError) do
          Registry.new.register(
            key: "downstream.too_wide",
            type: :counter,
            dimensions: {
              first: values,
              second: values,
              third: values
            }
          )
        end

        assert_equal "operations_metric_cardinality_too_high", error.message
      end

      test "bounds total registered cardinality to the default buffer capacity" do
        registry = Registry.new
        values = [ "other", *15.times.map { |index| "value_#{index}" } ]
        registry.register(
          key: "downstream.first",
          type: :counter,
          dimensions: { first: values, second: values }
        )
        registry.register(
          key: "downstream.second",
          type: :counter,
          dimensions: { first: values, second: values }
        )

        error = assert_raises(ArgumentError) do
          registry.register(key: "downstream.one_too_many", type: :counter)
        end

        assert_equal "operations_metrics_registry_cardinality_too_high",
          error.message
        assert_equal Registry::MAX_TOTAL_CARDINALITY,
          Buffer::DEFAULT_MAX_KEYS
      end
    end
  end
end
