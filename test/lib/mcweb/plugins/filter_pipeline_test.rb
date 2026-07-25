# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/registry"

class Mcweb::Plugins::FilterPipelineTest < ActiveSupport::TestCase
  class NullEventBus
    def subscribe(*) = Object.new
    def unsubscribe(*) = true
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

  test "filters run deterministically with immutable normalized values and context" do
    calls = []
    register("zeta/late") do |plugin|
      plugin.filter("forum.topic.create.attributes", priority: 20) do |value, context|
        calls << [ "zeta", value.frozen?, context.frozen? ]
        value.merge("title" => "#{value.fetch('title')} Z")
      end
    end
    register("alpha/same-priority") do |plugin|
      plugin.filter("forum.topic.create.attributes", priority: 20) do |value, context|
        calls << [ "alpha", value.frozen?, context.fetch("nested").frozen? ]
        value.merge("title" => "#{value.fetch('title')} A")
      end
    end
    register("beta/first") do |plugin|
      plugin.filter("forum.topic.create.attributes", priority: 5) do |value, context|
        assert_raises(FrozenError) { value["title"] = "mutated" }
        assert_raises(FrozenError) { context.fetch("nested") << "mutated" }
        calls << [ "beta", value.frozen?, context.frozen? ]
        value.merge("title" => "#{value.fetch('title')} B")
      end
    end
    @registry.boot!

    result = @registry.apply_filter(
      "forum.topic.create.attributes",
      { title: "Original" },
      context: { nested: [ "safe" ] }
    )

    assert_equal "Original B A Z", result.fetch("title")
    assert_equal %w[beta alpha zeta], calls.map(&:first)
    assert calls.all? { |entry| entry.drop(1).all? }
    assert_predicate result, :frozen?
    assert_equal 1, @registry.list.find { |entry| entry[:id] == "beta/first" }.fetch(:filter_count)
  end

  test "failures and incompatible root values are diagnosed and skipped" do
    register("alpha/error") do |plugin|
      plugin.filter("forum.post.create.attributes", priority: 1) { raise "boom" }
    end
    register("beta/wrong-shape") do |plugin|
      plugin.filter("forum.post.create.attributes", priority: 2) { [ "not", "a", "hash" ] }
    end
    register("gamma/good") do |plugin|
      plugin.filter("forum.post.create.attributes", priority: 3) do |value|
        value.merge("body" => "safe")
      end
    end
    @registry.boot!

    result = assert_nothing_raised do
      @registry.apply_filter("forum.post.create.attributes", { body: "original" })
    end

    assert_equal "safe", result.fetch("body")
    assert_equal "degraded", plugin("alpha/error").fetch(:status)
    assert_equal 1, plugin("alpha/error").fetch(:failure_count)
    assert @registry.diagnostics.any? { |entry| entry[:code] == "filter_error" && entry[:plugin_id] == "alpha/error" }
    assert @registry.diagnostics.any? do |entry|
      entry[:code] == "invalid_filter_result" && entry[:plugin_id] == "beta/wrong-shape"
    end
  end

  test "recursive application is bounded and undeclared extension capability is audited" do
    register("acme/recursive", capabilities: []) do |plugin|
      plugin.filter("forum.topic.create.attributes") do |value|
        @registry.apply_filter("forum.topic.create.attributes", value)
      end
    end
    @registry.boot!

    result = @registry.apply_filter("forum.topic.create.attributes", { title: "safe" })

    assert_equal "safe", result.fetch("title")
    assert @registry.diagnostics.any? { |entry| entry[:code] == "filter_recursion" }
    assert @registry.diagnostics.any? do |entry|
      entry[:code] == "undeclared_capability" &&
        entry[:plugin_id] == "acme/recursive" &&
        entry[:message].include?("forum.extend")
    end
  end

  test "invalid names and post-boot registration changes are rejected" do
    definition = register("acme/sealed")
    @registry.boot!

    assert_raises(ArgumentError) { @registry.apply_filter("invalid", {}) }
    assert_raises(Mcweb::Plugins::LifecycleError) do
      definition.filter("forum.topic.create.attributes") { |value| value }
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
