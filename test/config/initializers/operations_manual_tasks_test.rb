# frozen_string_literal: true

require "test_helper"

class OperationsManualTasksInitializerTest < ActiveSupport::TestCase
  KEY = Mcweb::OperationsManualTaskRegistrarConfig::KEY

  setup do
    @custom_config = Rails.application.config.x
    @store = @custom_config.instance_variable_get(:@configurations)
    @had_original_value = @store.key?(KEY)
    @original_value = @store[KEY]
    @store.delete(KEY)
    Operations::ManualTaskCatalog.reset_registry!
  end

  teardown do
    if @had_original_value
      @store[KEY] = @original_value
    else
      @store.delete(KEY)
    end
    Operations::ManualTaskCatalog.reset_registry!
  end

  test "boot initializes an absent registrar setting as a mutable array" do
    load_initializer

    registrars = @custom_config.operations_manual_task_registrars
    assert_instance_of Array, registrars
    assert_empty registrars
    refute_predicate registrars, :frozen?
    assert_same registrars, @store[KEY]
  end

  test "boot preserves a valid registrar array" do
    registrar = ->(_registry) { }
    configured = [ registrar ]
    @store[KEY] = configured

    load_initializer

    assert_same configured, @custom_config.operations_manual_task_registrars
    refute_predicate configured, :frozen?
  end

  test "a downstream initializer can append a registrar before catalog construction" do
    load_initializer
    registrars = @custom_config.operations_manual_task_registrars
    registrar = registrar_for("downstream.startup.probe")

    appended = Mcweb::OperationsManualTaskRegistrarConfig.register!(@custom_config, registrar)

    entry = Operations::ManualTaskCatalog.entry("downstream.startup.probe")

    assert_same registrar, appended
    assert_equal "downstream.startup.probe", entry.key
    assert_predicate registrars, :frozen?
    assert_predicate Operations::ManualTaskCatalog, :registry_frozen?
    error = assert_raises(FrozenError) do
      Mcweb::OperationsManualTaskRegistrarConfig.register!(
        @custom_config,
        registrar_for("downstream.too_late")
      )
    end
    assert_equal "operations_manual_task_registrars_frozen", error.message
  end

  test "boot rejects an invalid registrar container or element" do
    @store[KEY] = ActiveSupport::OrderedOptions.new
    container_error = assert_raises(TypeError) { load_initializer }
    assert_equal "operations_manual_task_registrars_must_be_array", container_error.message

    @store[KEY] = [ Object.new ]
    registrar_error = assert_raises(TypeError) { load_initializer }
    assert_equal "operations_manual_task_registrar_must_be_callable", registrar_error.message
  end

  test "public registration rejects a duplicate registrar instance" do
    registrar = registrar_for("downstream.duplicate.instance")
    @store[KEY] = []
    Mcweb::OperationsManualTaskRegistrarConfig.register!(@custom_config, registrar)

    error = assert_raises(ArgumentError) do
      Mcweb::OperationsManualTaskRegistrarConfig.register!(@custom_config, registrar)
    end

    assert_equal "operations_manual_task_registrar_duplicate", error.message
    assert_equal [ registrar ], @store[KEY]
  end

  test "catalog rejects distinct registrars that register the same task key" do
    load_initializer
    registrars = @custom_config.operations_manual_task_registrars
    Mcweb::OperationsManualTaskRegistrarConfig.register!(
      @custom_config,
      registrar_for("downstream.duplicate.task")
    )
    Mcweb::OperationsManualTaskRegistrarConfig.register!(
      @custom_config,
      registrar_for("downstream.duplicate.task")
    )

    error = assert_raises(ArgumentError) do
      Operations::ManualTaskCatalog.entry("downstream.duplicate.task")
    end

    assert_equal "manual_task_duplicate", error.message
    assert_predicate registrars, :frozen?
    assert_raises(ArgumentError) do
      Operations::ManualTaskCatalog.entry("downstream.duplicate.task")
    end
  end

  test "catalog rejects a registrar setting corrupted after boot" do
    load_initializer
    @store[KEY] = ActiveSupport::OrderedOptions.new

    container_error = assert_raises(TypeError) do
      Operations::ManualTaskCatalog.entry("downstream.never.visible")
    end
    assert_equal "operations_manual_task_registrars_must_be_array", container_error.message

    @store[KEY] = [ Object.new ]
    registrar_error = assert_raises(TypeError) do
      Operations::ManualTaskCatalog.entry("downstream.never.visible")
    end
    assert_equal "operations_manual_task_registrar_must_be_callable", registrar_error.message
  end

  test "registrar config rejects an unexpected Rails config object or store" do
    config_error = assert_raises(TypeError) do
      Mcweb::OperationsManualTaskRegistrarConfig.initialize!(Object.new)
    end
    assert_equal "operations_manual_task_config_invalid", config_error.message

    custom_config = Rails::Application::Configuration::Custom.new
    custom_config.instance_variable_set(:@configurations, [])
    store_error = assert_raises(TypeError) do
      Mcweb::OperationsManualTaskRegistrarConfig.initialize!(custom_config)
    end
    assert_equal "operations_manual_task_config_store_invalid", store_error.message
  end

  private

  def load_initializer
    load Rails.root.join("config/initializers/operations_manual_tasks.rb")
  end

  def registrar_for(key)
    lambda do |registry|
      registry.register(
        key: key,
        label_key: "operations.test.label",
        description_key: "operations.test.description",
        permissions: [ "system.jobs.manage" ]
      ) { |_run| { ok: true } }
    end
  end
end
