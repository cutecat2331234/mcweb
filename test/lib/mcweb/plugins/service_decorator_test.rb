# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/registry"

class Mcweb::Plugins::ServiceDecoratorTest < ActiveSupport::TestCase
  class NullEventBus
    def subscribe(*) = Object.new
    def unsubscribe(*) = true
  end

  class CoreFailure < StandardError; end

  class NativeResult
    attr_accessor :value

    def initialize(value)
      @value = value
    end
  end

  setup do
    @registry = Mcweb::Plugins::Registry.new(
      event_bus: NullEventBus.new,
      logger: Logger.new(IO::NULL)
    )
  end

  teardown do
    @registry.reset!
  end

  test "decorators wrap services deterministically with immutable normalized boundaries" do
    calls = []
    register("zeta/late") do |plugin|
      plugin.decorate_service("forum.topic.create", priority: 20) do |proceed, input, context|
        calls << "zeta.before"
        assert_predicate input, :frozen?
        assert_predicate context, :frozen?
        result = proceed.call(input.merge("title" => "#{input.fetch('title')} Z"))
        calls << "zeta.after"
        result.merge("trace" => result.fetch("trace") + [ "zeta" ])
      end
    end
    register("alpha/same-priority") do |plugin|
      plugin.decorate_service("forum.topic.create", priority: 20) do |proceed, input, context|
        calls << "alpha.before"
        assert_raises(FrozenError) { context.fetch("nested") << "mutated" }
        result = proceed.call(input.merge("title" => "#{input.fetch('title')} A"))
        calls << "alpha.after"
        result.merge("trace" => result.fetch("trace") + [ "alpha" ])
      end
    end
    register("beta/first") do |plugin|
      plugin.decorate_service("forum.topic.create", priority: 5) do |proceed, input, context|
        calls << "beta.before"
        assert_raises(FrozenError) { input["title"] = "mutated" }
        assert_predicate context.fetch("nested"), :frozen?
        result = proceed.call(input.merge("title" => "#{input.fetch('title')} B"))
        calls << "beta.after"
        result.merge("trace" => result.fetch("trace") + [ "beta" ])
      end
    end
    @registry.boot!

    core_calls = 0
    result = @registry.call_service(
      "forum.topic.create",
      input: { title: "Original" },
      context: { nested: [ "safe" ] }
    ) do |input, context|
      core_calls += 1
      calls << "core"
      assert_predicate input, :frozen?
      assert_predicate context, :frozen?
      { "title" => input.fetch("title"), "trace" => [ "core" ] }
    end

    assert_equal 1, core_calls
    assert_equal "Original B A Z", result.fetch("title")
    assert_equal %w[core zeta alpha beta], result.fetch("trace")
    assert_equal(
      %w[beta.before alpha.before zeta.before core zeta.after alpha.after beta.after],
      calls
    )
    assert_equal 1, plugin("beta/first").fetch(:service_decorator_count)
  end

  test "decorator failures and invalid results fall back without repeating the core operation" do
    register("alpha/before-error") do |plugin|
      plugin.decorate_service("forum.topic.create", priority: 1) { raise "before boom" }
    end
    register("beta/multiple") do |plugin|
      plugin.decorate_service("forum.topic.create", priority: 2) do |proceed|
        first = proceed.call
        second = proceed.call("ignored" => true)
        assert_same first, second
        first
      end
    end
    register("gamma/wrong-shape") do |plugin|
      plugin.decorate_service("forum.topic.create", priority: 3) do |proceed|
        proceed.call
        [ "not", "a", "hash" ]
      end
    end
    register("delta/after-error") do |plugin|
      plugin.decorate_service("forum.topic.create", priority: 4) do |proceed|
        proceed.call
        raise "after boom"
      end
    end
    register("epsilon/good") do |plugin|
      plugin.decorate_service("forum.topic.create", priority: 5) do |proceed|
        proceed.call.merge("decorated" => true)
      end
    end
    @registry.boot!

    core_calls = 0
    result = assert_nothing_raised do
      @registry.call_service("forum.topic.create", input: { title: "safe" }) do |input|
        core_calls += 1
        { "title" => input.fetch("title") }
      end
    end

    assert_equal 1, core_calls
    assert_equal({ "title" => "safe", "decorated" => true }, result)
    assert_equal "degraded", plugin("alpha/before-error").fetch(:status)
    assert_equal 1, plugin("alpha/before-error").fetch(:failure_count)
    assert_equal "degraded", plugin("delta/after-error").fetch(:status)
    assert_equal 1, plugin("delta/after-error").fetch(:failure_count)
    assert @registry.diagnostics.any? do |entry|
      entry[:code] == "service_decorator_error" && entry[:plugin_id] == "alpha/before-error"
    end
    assert @registry.diagnostics.any? do |entry|
      entry[:code] == "invalid_service_decorator_result" && entry[:plugin_id] == "gamma/wrong-shape"
    end
    assert @registry.diagnostics.any? do |entry|
      entry[:code] == "service_decorator_multiple_proceed" && entry[:plugin_id] == "beta/multiple"
    end
  end

  test "a decorator cannot suppress the core operation" do
    register("acme/skips-core") do |plugin|
      plugin.decorate_service("identity.permission.check") do
        { "allowed" => true, "source" => "plugin" }
      end
    end
    @registry.boot!

    core_calls = 0
    result = @registry.call_service("identity.permission.check") do
      core_calls += 1
      { "allowed" => false, "source" => "core" }
    end

    assert_equal 1, core_calls
    assert_equal({ "allowed" => false, "source" => "core" }, result)
    assert_equal "degraded", plugin("acme/skips-core").fetch(:status)
    assert_equal 1, plugin("acme/skips-core").fetch(:failure_count)
    assert @registry.diagnostics.any? do |entry|
      entry[:code] == "service_decorator_skipped_core" && entry[:plugin_id] == "acme/skips-core"
    end
  end

  test "an incompatible continuation input is attributed to the plugin and safely retried" do
    register("acme/wrong-input") do |plugin|
      plugin.decorate_service("forum.topic.create") do |proceed|
        proceed.call([ "not", "a", "hash" ])
      end
    end
    @registry.boot!

    core_calls = 0
    result = assert_nothing_raised do
      @registry.call_service(
        "forum.topic.create",
        input: { title: "safe" }
      ) do |input|
        core_calls += 1
        { "title" => input.fetch("title") }
      end
    end

    assert_equal 1, core_calls
    assert_equal({ "title" => "safe" }, result)
    assert_equal "degraded", plugin("acme/wrong-input").fetch(:status)
    assert_equal 1, plugin("acme/wrong-input").fetch(:failure_count)
    assert @registry.diagnostics.any? do |entry|
      entry[:code] == "service_decorator_error" &&
        entry[:plugin_id] == "acme/wrong-input" &&
        entry[:message].include?("root input type from hash to array")
    end
  end

  test "host-native service results preserve identity and remain mutable" do
    register("acme/native-result") do |plugin|
      plugin.decorate_service("forum.topic.create") do |proceed|
        proceed.call.tap { |result| result.value = "decorated" }
      end
    end
    @registry.boot!

    core_result = NativeResult.new("core")
    result = @registry.call_service("forum.topic.create") { core_result }

    assert_same core_result, result
    assert_instance_of NativeResult, result
    assert_equal "decorated", result.value
    assert_not_predicate result, :frozen?
  end

  test "concurrent continuation calls still execute the core operation once" do
    register("acme/concurrent") do |plugin|
      plugin.decorate_service("forum.topic.create") do |proceed|
        results = Array.new(8) do
          Thread.new { proceed.call }
        end.map(&:value)
        assert_equal 1, results.map(&:object_id).uniq.length
        results.first
      end
    end
    @registry.boot!

    core_calls = 0
    core_mutex = Mutex.new
    result = @registry.call_service("forum.topic.create") do
      core_mutex.synchronize { core_calls += 1 }
      sleep 0.01
      { "source" => "core" }
    end

    assert_equal 1, core_calls
    assert_equal({ "source" => "core" }, result)
    assert @registry.diagnostics.any? do |entry|
      entry[:code] == "service_decorator_multiple_proceed" &&
        entry[:plugin_id] == "acme/concurrent"
    end
  end

  test "a running continuation cannot wait on its own result" do
    continuation = nil
    continuation = Mcweb::Plugins::ServiceContinuation.new(
      default_input: {},
      normalizer: Mcweb::PluginApi::V1::Normalizer.method(:call),
      input_validator: ->(*) { nil }
    ) do
      continuation.result
    end

    error = assert_raises(Mcweb::Plugins::LifecycleError) { continuation.call }

    assert_equal "service continuation result is unavailable while it is running", error.message
    assert_same error, assert_raises(Mcweb::Plugins::LifecycleError) { continuation.result }
  end

  test "continuations preserve the recursion guard when a plugin uses a worker thread" do
    decorator_calls = 0
    register("acme/threaded") do |plugin|
      plugin.decorate_service("forum.topic.create") do |proceed|
        decorator_calls += 1
        Thread.new { proceed.call }.value
      end
    end
    @registry.boot!

    core_calls = 0
    result = @registry.call_service("forum.topic.create") do
      core_calls += 1
      nested = @registry.call_service("forum.topic.create") do
        core_calls += 1
        { "source" => "nested" }
      end
      { "source" => "outer", "nested" => nested }
    end

    assert_equal 1, decorator_calls
    assert_equal 2, core_calls
    assert_equal "nested", result.dig("nested", "source")
    assert @registry.diagnostics.any? { |entry| entry[:code] == "service_recursion" }
  end

  test "core failures propagate without being attributed to decorators" do
    register("acme/recovery-attempt") do |plugin|
      plugin.decorate_service("forum.topic.create") do |proceed|
        proceed.call
      rescue CoreFailure
        { "masked" => true }
      end
    end
    @registry.boot!

    error = assert_raises(CoreFailure) do
      @registry.call_service("forum.topic.create") { raise CoreFailure, "core boom" }
    end

    assert_equal "core boom", error.message
    assert_equal "active", plugin("acme/recovery-attempt").fetch(:status)
    assert_equal 0, plugin("acme/recovery-attempt").fetch(:failure_count)
    assert_not @registry.diagnostics.any? { |entry| entry[:code] == "service_decorator_error" }
  end

  test "non-standard core exceptions are memoized for every continuation waiter" do
    observed = []
    register("acme/fatal-observer") do |plugin|
      plugin.decorate_service("forum.topic.create") do |proceed|
        observed.concat(
          Array.new(4) do
            Thread.new do
              proceed.call
            rescue Exception => e # rubocop:disable Lint/RescueException
              e
            end
          end.map(&:value)
        )
        raise observed.first
      end
    end
    @registry.boot!

    core_error = ScriptError.new("fatal core boom")
    raised = assert_raises(ScriptError) do
      @registry.call_service("forum.topic.create") { raise core_error }
    end

    assert_same core_error, raised
    assert_equal 4, observed.length
    assert observed.all? { |error| error.equal?(core_error) }
    assert_equal "active", plugin("acme/fatal-observer").fetch(:status)
  end

  test "recursive decoration is bounded and undeclared capabilities are audited" do
    decorator_calls = 0
    core_calls = []
    register("acme/recursive", capabilities: []) do |plugin|
      plugin.decorate_service("forum.topic.create") do |proceed, input|
        decorator_calls += 1
        assert_raises(ArgumentError) do
          @registry.call_service("invalid") { raise "must not run" }
        end
        nested = @registry.call_service(
          "forum.topic.create",
          input: { source: "nested" }
        ) do |nested_input|
          core_calls << nested_input.fetch("source")
          { "source" => nested_input.fetch("source") }
        end
        proceed.call(input).merge("nested" => nested)
      end
    end
    @registry.boot!

    result = @registry.call_service(
      "forum.topic.create",
      input: { source: "outer" }
    ) do |input|
      core_calls << input.fetch("source")
      { "source" => input.fetch("source") }
    end

    assert_equal 1, decorator_calls
    assert_equal %w[nested outer], core_calls
    assert_equal "outer", result.fetch("source")
    assert_equal "nested", result.dig("nested", "source")
    assert @registry.diagnostics.any? { |entry| entry[:code] == "service_recursion" }
    assert @registry.diagnostics.any? do |entry|
      entry[:code] == "undeclared_capability" &&
        entry[:plugin_id] == "acme/recursive" &&
        entry[:message].include?("forum.extend")
    end
  end

  test "invalid names missing core operations and post-boot changes are rejected" do
    definition = register("acme/sealed")
    @registry.boot!

    assert_raises(ArgumentError) { @registry.call_service("invalid") { nil } }
    assert_raises(ArgumentError) { @registry.call_service("forum.topic.create") }
    assert_raises(Mcweb::Plugins::LifecycleError) do
      definition.decorate_service("forum.topic.create") { |proceed| proceed.call }
    end
  end

  private

  def register(id, capabilities: [ "forum.extend" ], &block)
    @registry.register(
      id:,
      name: id,
      version: "1.0.0",
      api_version: "1",
      requires: {},
      capabilities:,
      &block
    )
  end

  def plugin(id)
    @registry.list.find { |entry| entry[:id] == id }
  end
end
