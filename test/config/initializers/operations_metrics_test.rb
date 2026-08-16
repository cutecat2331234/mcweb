# frozen_string_literal: true

require "test_helper"

class OperationsMetricsInitializerTest < ActiveSupport::TestCase
  KEY = Mcweb::OperationsMetricsRegistrarConfig::KEY
  CATALOG = Operations::Metrics::Catalog

  test "application boot freezes the metric catalog and registrar list" do
    registrars = Rails.application.config.x.operations_metrics_registrars

    assert_predicate CATALOG, :registry_frozen?
    assert_predicate registrars, :frozen?
    assert_not_respond_to CATALOG, :register

    error = assert_raises(FrozenError) do
      Mcweb::OperationsMetricsRegistrarConfig.register!(
        Rails.application.config.x,
        ->(_registry) { }
      )
    end
    assert_equal "operations_metrics_registrars_frozen", error.message
  end

  test "boot registrars add typed metrics before the catalog freezes" do
    registrar = lambda do |registry|
      registry.register(
        key: "downstream.maintenance.run",
        type: :counter,
        dimensions: {
          outcome: %w[success failure other],
          mode: %w[ranked unranked other]
        }
      )
    end

    with_isolated_catalog([ registrar ]) do
      entry = CATALOG.definition("downstream.maintenance.run")
      normalized = CATALOG.normalize(
        entry.key,
        value: 1,
        dimensions: {
          outcome: "success",
          mode: "private-account-42",
          account_id: 42
        }
      )

      assert_equal "counter", entry.type
      assert_equal(
        { "mode" => "other", "outcome" => "success" },
        normalized.dimensions
      )
      assert_includes CATALOG.metric_names, entry.key
      assert_predicate CATALOG, :registry_frozen?
      assert_predicate current_registrars, :frozen?

      now = Time.zone.parse("2026-08-16 12:00:00")
      written = []
      Operations::Metrics.buffer = Operations::Metrics::Buffer.new(
        clock: -> { now },
        writer: ->(entries) { written.concat(entries) }
      )
      assert Operations::Metrics.record(
        entry.key,
        dimensions: { outcome: "success", mode: "ranked" },
        at: now
      )
      assert_equal 1, Operations::Metrics.flush!(now:)
      assert_equal entry.key, written.fetch(0).fetch(:metric_name)

      bucket = Operations::MetricBucket.new(
        bucket_at: Time.current,
        metric_name: entry.key,
        dimensions: normalized.dimensions,
        dimensions_key: normalized.dimensions_key,
        sample_count: 1,
        value_sum: 1,
        value_min: 1,
        value_max: 1
      )
      assert_predicate bucket, :valid?
    ensure
      Operations::Metrics.reset!
    end
  end

  test "equivalent definitions from separate registrars are idempotent" do
    first = lambda do |registry|
      registry.register(
        key: "downstream.queue.depth",
        type: :gauge,
        dimensions: { mode: %w[ranked other] }
      )
    end
    second = lambda do |registry|
      registry.register(
        key: "downstream.queue.depth",
        type: "gauge",
        dimensions: { "mode" => %w[other ranked] }
      )
    end

    with_isolated_catalog([ first, second ]) do
      assert_equal 1,
        CATALOG.metric_names.count { |key| key == "downstream.queue.depth" }
    end
  end

  test "conflicting boot definitions leave the catalog unavailable" do
    first = registrar_for(type: :gauge)
    second = registrar_for(type: :counter)

    with_isolated_catalog([ first, second ], finalize: false) do
      Rails.application.stub(:initialized?, false) do
        error = assert_raises(ArgumentError) { CATALOG.finalize! }

        assert_equal "operations_metric_definition_conflict", error.message
      end
      assert_not_predicate CATALOG, :registry_frozen?
      assert_predicate current_registrars, :frozen?
      assert_raises(FrozenError) do
        CATALOG.normalize("downstream.conflict", value: 1, dimensions: {})
      end
    end
  end

  test "an unfinalized catalog cannot be opened after boot" do
    with_isolated_catalog([], finalize: false) do
      Rails.application.stub(:initialized?, true) do
        error = assert_raises(FrozenError) { CATALOG.finalize! }

        assert_equal "operations_metrics_catalog_boot_closed", error.message
      end
      assert_not_predicate CATALOG, :registry_frozen?
    end
  end

  test "a development reload rebuilds only from the frozen boot registration" do
    registrar = lambda do |registry|
      registry.register(key: "downstream.reload.safe", type: :counter)
    end

    with_isolated_catalog([ registrar ]) do
      frozen_registrars = current_registrars
      CATALOG.remove_instance_variable(:@registry)
      CATALOG.remove_instance_variable(:@boot_finalized)

      Rails.application.stub(:initialized?, true) { CATALOG.finalize! }

      assert_same frozen_registrars, current_registrars
      assert_predicate current_registrars, :frozen?
      assert_predicate CATALOG, :registry_frozen?
      assert CATALOG.registered?("downstream.reload.safe")
    end
  end

  test "registrar instance registration is idempotent before boot closes" do
    registrar = ->(_registry) { }

    with_isolated_catalog([], finalize: false) do
      first = Mcweb::OperationsMetricsRegistrarConfig.register!(
        Rails.application.config.x,
        registrar
      )
      duplicate = Mcweb::OperationsMetricsRegistrarConfig.register!(
        Rails.application.config.x,
        registrar
      )

      assert_same registrar, first
      assert_same first, duplicate
      assert_equal [ registrar ], current_registrars
    end
  end

  test "catalog rejects a corrupted registrar configuration" do
    with_isolated_catalog(ActiveSupport::OrderedOptions.new, finalize: false) do
      Rails.application.stub(:initialized?, false) do
        error = assert_raises(TypeError) { CATALOG.finalize! }
        assert_equal "operations_metrics_registrars_must_be_array",
          error.message
      end
    end

    with_isolated_catalog([ Object.new ], finalize: false) do
      Rails.application.stub(:initialized?, false) do
        error = assert_raises(TypeError) { CATALOG.finalize! }
        assert_equal "operations_metrics_registrar_must_be_callable",
          error.message
      end
    end
  end

  private

  def with_isolated_catalog(registrars, finalize: true)
    store = config_store
    original_registrars = store[KEY]
    registry_defined = CATALOG.instance_variable_defined?(:@registry)
    original_registry = CATALOG.instance_variable_get(:@registry)
    finalized_defined = CATALOG.instance_variable_defined?(:@boot_finalized)
    original_finalized = CATALOG.instance_variable_get(:@boot_finalized)

    store[KEY] = registrars
    CATALOG.remove_instance_variable(:@registry) if registry_defined
    CATALOG.remove_instance_variable(:@boot_finalized) if finalized_defined
    if finalize
      Rails.application.stub(:initialized?, false) { CATALOG.finalize! }
    end
    yield
  ensure
    store[KEY] = original_registrars
    CATALOG.remove_instance_variable(:@registry) if
      CATALOG.instance_variable_defined?(:@registry)
    CATALOG.remove_instance_variable(:@boot_finalized) if
      CATALOG.instance_variable_defined?(:@boot_finalized)
    CATALOG.instance_variable_set(:@registry, original_registry) if
      registry_defined
    CATALOG.instance_variable_set(:@boot_finalized, original_finalized) if
      finalized_defined
  end

  def config_store
    Rails.application.config.x.instance_variable_get(:@configurations)
  end

  def current_registrars
    config_store.fetch(KEY)
  end

  def registrar_for(type:)
    lambda do |registry|
      registry.register(
        key: "downstream.conflict",
        type:,
        dimensions: {}
      )
    end
  end
end
