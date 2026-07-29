# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/registry"

class Mcweb::Plugins::RegistryTest < ActiveSupport::TestCase
  class FakeEventBus
    Handle = Data.define(:event, :callback)

    def initialize
      @listeners = Hash.new { |hash, key| hash[key] = [] }
      @mutex = Mutex.new
    end

    def subscribe(event, &callback)
      handle = Handle.new(event:, callback:)
      @mutex.synchronize { @listeners[event] << handle }
      handle
    end

    def unsubscribe(handle)
      @mutex.synchronize { @listeners[handle.event].delete(handle) }
    end

    def publish(event, payload = {})
      listeners = @mutex.synchronize { @listeners[event].dup }
      listeners.each { |handle| handle.callback.call(payload) }
    end

    def subscription_count(event)
      @mutex.synchronize { @listeners[event].length }
    end
  end

  class SlowEventBus < FakeEventBus
    def subscribe(...)
      sleep(0.01)
      super
    end
  end

  setup do
    @event_bus = FakeEventBus.new
    @registry = Mcweb::Plugins::Registry.new(event_bus: @event_bus, logger: Logger.new(IO::NULL))
    @previous_disable_plugins = ENV["MCWEB_DISABLE_PLUGINS"]
    ENV.delete("MCWEB_DISABLE_PLUGINS")
  end

  teardown do
    @registry.reset!
    if @previous_disable_plugins.nil?
      ENV.delete("MCWEB_DISABLE_PLUGINS")
    else
      ENV["MCWEB_DISABLE_PLUGINS"] = @previous_disable_plugins
    end
  end

  test "register validates strict manifest fields and rejects duplicate ids" do
    definition = register("acme/demo", version: "1.2.3-beta.1+build.5")

    assert_equal "acme/demo", definition.id
    assert_equal Gem::Version.new("1.2.3.pre.beta.1"), definition.manifest.version_object
    assert_raises(Mcweb::Plugins::DuplicatePluginError) { register("acme/demo") }

    invalid_manifests = [
      base_manifest(id: "demo"),
      base_manifest(version: "1.2"),
      base_manifest(version: "01.2.3"),
      base_manifest(name: 123),
      base_manifest(api_version: 1),
      base_manifest(description: 123),
      base_manifest(api_version: "99"),
      base_manifest(requires: { "bad" => ">= 1.0.0" }),
      base_manifest(requires: { "base/core": ">= 1.0.0" }),
      base_manifest(requires: { "acme/demo" => "not a requirement" }),
      base_manifest(capabilities: [ "not_namespaced" ])
    ]
    invalid_manifests.each do |manifest|
      assert_raises(Mcweb::Plugins::ManifestError) do
        Mcweb::Plugins::Manifest.from_hash(manifest)
      end
    end
  end

  test "manifest owns and deeply freezes all exposed values" do
    id = +"acme/demo"
    name = +"Demo"
    version = +"1.0.0"
    api_version = +"1"
    description = +"Description"
    author = +"Acme"
    homepage = +"https://example.test"
    dependency_id = +"base/core"
    requirement = +">= 1.0.0"
    capability = +"forum.events.read"
    entrypoint = +"plugin.rb"
    source_path = +"C:/plugins/acme-demo/mcweb_plugin.yml"
    attributes = {
      id:,
      name:,
      version:,
      api_version:,
      description:,
      author:,
      homepage:,
      requires: { dependency_id => requirement },
      capabilities: [ capability ],
      entrypoint:
    }

    manifest = Mcweb::Plugins::Manifest.from_hash(attributes, source_path:)
    [ id, name, version, api_version, description, author, homepage,
      dependency_id, requirement, capability, entrypoint, source_path ].each { |value| value << "-changed" }

    assert_equal "acme/demo", manifest.id
    assert_equal "Demo", manifest.name
    assert_equal "1.0.0", manifest.version
    assert_equal "1", manifest.api_version
    assert_equal "Description", manifest.description
    assert_equal "Acme", manifest.author
    assert_equal "https://example.test", manifest.homepage
    assert_equal({ "base/core" => ">= 1.0.0" }, manifest.requires)
    assert_equal [ "forum.events.read" ], manifest.capabilities
    assert_equal "plugin.rb", manifest.entrypoint
    assert_equal "C:/plugins/acme-demo/mcweb_plugin.yml", manifest.source_path

    exposed = [
      manifest.id, manifest.name, manifest.version, manifest.api_version,
      manifest.description, manifest.author, manifest.homepage,
      manifest.requires, *manifest.requires.keys, *manifest.requires.values,
      manifest.capabilities, *manifest.capabilities, manifest.entrypoint,
      manifest.source_path, manifest.version_object, manifest.to_h
    ]
    exposed.each { |value| assert_predicate value, :frozen? }
    assert_raises(FrozenError) { manifest.to_h.fetch(:requires).keys.first << "-changed" }

    requirement_object = manifest.requirement_for("base/core")
    assert_predicate requirement_object, :frozen?
    assert_predicate requirement_object.requirements, :frozen?
    assert_raises(FrozenError) do
      requirement_object.requirements << [ ">=", Gem::Version.new("2.0.0") ]
    end

    assert_raises(Mcweb::Plugins::ManifestError) do
      Mcweb::Plugins::Manifest.from_hash(
        {
          id: "acme/one",
          "id" => "acme/two",
          name: "Duplicate keys",
          version: "1.0.0",
          api_version: "1"
        }
      )
    end
  end

  test "dispatch order is priority then plugin id and a central event has one subscription" do
    calls = []
    register("zeta/listener") { |plugin| plugin.on("forum.post.created", priority: 20) { calls << "zeta" } }
    register("alpha/second") { |plugin| plugin.on("forum.post.created", priority: 20) { calls << "alpha" } }
    register("beta/first") { |plugin| plugin.on("forum.post.created", priority: 5) { calls << "beta" } }

    @registry.boot!
    assert_equal 1, @event_bus.subscription_count("forum.post.created")

    @event_bus.publish("forum.post.created", value: 1)
    assert_equal %w[beta alpha zeta], calls
  end

  test "event DTO is immutable versioned and normalizes records without model access" do
    received = nil
    register("acme/snapshot") do |plugin|
      plugin.on("forum.user.snapshot") { |event| received = event }
    end
    @registry.boot!

    user = create_user(username: "plugin_snapshot_user")
    public_id = user.public_id
    @event_bus.publish("forum.user.snapshot", user:, nested: { values: [ "one" ] })

    assert_equal "1", received.schema_version
    assert_match(/\A[0-9a-f-]{36}\z/, received.event_id)
    assert_predicate received, :frozen?
    assert_predicate received.data, :frozen?
    assert_equal(
      { "type" => "User", "id" => user.id, "public_id" => user.public_id },
      received.data.fetch("user")
    )
    refute_includes received.data.fetch("user").keys, "email"
    refute_predicate public_id, :frozen?
    assert_predicate received.to_h.fetch(:occurred_at), :frozen?
    assert_raises(FrozenError) { received.data["new"] = "value" }
    assert_raises(FrozenError) { received.data.dig("nested", "values") << "two" }
  end

  test "listener failures are isolated and recorded as degraded" do
    calls = []
    register("alpha/bad") { |plugin| plugin.on("forum.test.failure") { raise "boom" } }
    register("beta/good") { |plugin| plugin.on("forum.test.failure") { calls << "good" } }
    @registry.boot!

    assert_nothing_raised { @event_bus.publish("forum.test.failure") }
    assert_equal [ "good" ], calls
    assert_equal "degraded", plugin("alpha/bad").fetch(:status)
    assert_equal 1, plugin("alpha/bad").fetch(:failure_count)
    assert @registry.diagnostics.any? { |entry| entry[:code] == "listener_error" && entry[:plugin_id] == "alpha/bad" }
  end

  test "dependencies activate topologically and incompatible plugins have diagnostics" do
    register("base/core", version: "1.5.0")
    register("addon/good", requires: { "base/core" => ">= 1.0.0" })
    register("addon/version", requires: { "base/core" => ">= 2.0.0" })
    register("addon/missing", requires: { "missing/core" => ">= 1.0.0" })

    @registry.boot!

    assert_equal "active", plugin("base/core").fetch(:status)
    assert_equal "active", plugin("addon/good").fetch(:status)
    assert_operator plugin("base/core").fetch(:activation_order), :<, plugin("addon/good").fetch(:activation_order)
    assert_equal "disabled", plugin("addon/version").fetch(:status)
    assert_equal "disabled", plugin("addon/missing").fetch(:status)
    codes = @registry.diagnostics.map { |entry| entry[:code] }
    assert_includes codes, "dependency_version_mismatch"
    assert_includes codes, "missing_dependency"
  end

  test "dependency cycles are disabled" do
    register("cycle/one", requires: { "cycle/two" => ">= 1.0.0" })
    register("cycle/two", requires: { "cycle/one" => ">= 1.0.0" })

    @registry.boot!

    assert_equal "disabled", plugin("cycle/one").fetch(:status)
    assert_equal "disabled", plugin("cycle/two").fetch(:status)
    assert_equal 2, @registry.diagnostics.count { |entry| entry[:code] == "dependency_cycle" }
  end

  test "capabilities are audited declarations rather than a sandbox" do
    definition = register("acme/no-declaration", capabilities: []) do |plugin|
      plugin.on("forum.audit.allowed") { nil }
    end

    assert_nothing_raised { @registry.boot! }
    assert_predicate definition.api.site.features, :success?
    assert_predicate definition.api.site.features, :success?
    assert_predicate definition.api.forum.sections(user: nil), :success?
    assert_equal "active", plugin("acme/no-declaration").fetch(:status)
    listener_diagnostic = @registry.diagnostics.any? do |entry|
      entry[:code] == "undeclared_capability" && entry[:plugin_id] == "acme/no-declaration"
    end
    assert listener_diagnostic
    runtime_diagnostics = @registry.diagnostics.select do |entry|
      entry[:code] == "undeclared_capability" &&
        entry[:plugin_id] == "acme/no-declaration" &&
        entry[:phase] == "runtime"
    end
    assert_equal %w[forum.read site.features.read], runtime_diagnostics.pluck(:message).map { |message|
      message.split.first
    }.sort
  end

  test "disable switch prevents activation and dispatch" do
    calls = []
    register("acme/disabled") { |plugin| plugin.on("forum.disabled") { calls << true } }
    ENV["MCWEB_DISABLE_PLUGINS"] = "1"

    @registry.boot!
    @event_bus.publish("forum.disabled")

    assert_empty calls
    assert_equal "disabled", plugin("acme/disabled").fetch(:status)
    assert @registry.diagnostics.any? { |entry| entry[:code] == "plugins_disabled" }
  end

  test "fulfillment providers are namespaced immutable and strictly validated" do
    received = nil
    definition = register(
      "acme/fulfillment",
      capabilities: [ "commerce.fulfillments.write" ]
    ) do |plugin|
      plugin.fulfillment_provider("delivery") do |request|
        received = request
        {
          status: "succeeded",
          external_reference: "provider-reference"
        }
      end
    end

    assert_raises(Mcweb::Plugins::LifecycleError) do
      definition.fulfillment_provider("delivery") { { status: "succeeded" } }
    end

    @registry.boot!
    assert_equal(
      [ "acme/fulfillment:delivery" ],
      @registry.fulfillment_providers.pluck(:id)
    )

    result = @registry.dispatch_fulfillment(
      provider_id: "acme/fulfillment:delivery",
      request: {
        delivery_id: "delivery-one",
        nested: { values: [ "one" ] }
      }
    )

    assert_equal "succeeded", result.fetch("status")
    assert_equal "provider-reference", result.fetch("external_reference")
    assert_predicate result, :frozen?
    assert_predicate received, :frozen?
    assert_predicate received.dig("nested", "values"), :frozen?
    assert_raises(FrozenError) { received["delivery_id"] << "-changed" }

    definition = register("acme/invalid-provider") do |plugin|
      plugin.fulfillment_provider("delivery") { { status: "maybe", secret: "no" } }
    end
    @registry.boot!
    error = assert_raises(Mcweb::Plugins::FulfillmentProviderError) do
      @registry.dispatch_fulfillment(
        provider_id: "acme/invalid-provider:delivery",
        request: { delivery_id: "delivery-two" }
      )
    end
    assert_equal "provider_response_invalid", error.code
    assert_equal "degraded", plugin("acme/invalid-provider").fetch(:status)
    assert @registry.diagnostics.any? do |entry|
      entry[:code] == "fulfillment_provider_response_invalid" &&
        entry[:plugin_id] == definition.id
    end
  end

  test "disabled and unknown fulfillment providers never dispatch" do
    calls = 0
    register("acme/provider") do |plugin|
      plugin.fulfillment_provider("default") do
        calls += 1
        { status: "succeeded" }
      end
    end

    ENV["MCWEB_DISABLE_PLUGINS"] = "1"
    @registry.boot!

    error = assert_raises(Mcweb::Plugins::FulfillmentProviderError) do
      @registry.dispatch_fulfillment(
        provider_id: "acme/provider:default",
        request: {}
      )
    end
    assert_equal "provider_unavailable", error.code
    assert_equal 0, calls
  end

  test "boot and reset unsubscribe old central listeners" do
    calls = []
    register("acme/reload") { |plugin| plugin.on("forum.reload") { calls << true } }

    @registry.boot!
    @registry.boot!
    assert_equal 1, @event_bus.subscription_count("forum.reload")
    @event_bus.publish("forum.reload")
    assert_equal 1, calls.length

    @registry.reset!
    assert_equal 0, @event_bus.subscription_count("forum.reload")
    @event_bus.publish("forum.reload")
    assert_equal 1, calls.length
  end

  test "concurrent boots serialize subscription replacement" do
    event_bus = SlowEventBus.new
    registry = Mcweb::Plugins::Registry.new(
      event_bus:,
      logger: Logger.new(IO::NULL)
    )
    registry.register(base_manifest(id: "acme/concurrent")) do |plugin|
      plugin.on("forum.concurrent.boot") { nil }
    end

    threads = 8.times.map { Thread.new { registry.boot! } }
    threads.each(&:value)

    assert_equal 1, event_bus.subscription_count("forum.concurrent.boot")
    assert_equal "active", registry.list.first.fetch(:status)
  ensure
    registry&.reset!
  end

  test "concurrent listener failures update immutable runtime diagnostics atomically" do
    register("acme/concurrent-failure") do |plugin|
      plugin.on("forum.concurrent.failure") { raise "concurrent boom" }
    end
    @registry.boot!

    threads = 40.times.map do
      Thread.new { @event_bus.publish("forum.concurrent.failure") }
    end
    threads.each(&:value)

    snapshot = plugin("acme/concurrent-failure")
    assert_equal "degraded", snapshot.fetch(:status)
    assert_equal 40, snapshot.fetch(:failure_count)
    assert_equal 40, @registry.diagnostics.count { |entry| entry[:code] == "listener_error" }
    assert_predicate snapshot, :frozen?
    assert_predicate @registry.diagnostics, :frozen?
  end

  test "event normalization failures are isolated and diagnosed" do
    exploding_hash = Class.new(Hash) do
      def each(*)
        raise "cannot enumerate payload"
      end
    end.new
    calls = []
    register("acme/normalization") do |plugin|
      plugin.on("forum.normalization.failure") { calls << true }
    end
    @registry.boot!

    assert_nothing_raised do
      @event_bus.publish("forum.normalization.failure", exploding_hash)
    end

    assert_empty calls
    diagnostic = @registry.diagnostics.find do |entry|
      entry[:code] == "event_normalization_failed"
    end
    assert diagnostic
    assert_equal "RuntimeError", diagnostic.fetch(:exception)
  end

  test "diagnostics are bounded sanitized and immutable" do
    plugin_id = +"acme/mutable"
    event = +"forum.mutable"
    owned_diagnostic = @registry.record_diagnostic(
      level: :warning,
      code: :owned,
      phase: :runtime,
      message: "owned",
      plugin_id: plugin_id,
      event: event
    )
    plugin_id << ".changed"
    event << ".changed"

    assert_equal "acme/mutable", owned_diagnostic.fetch(:plugin_id)
    assert_equal "forum.mutable", owned_diagnostic.fetch(:event)
    assert_predicate owned_diagnostic.fetch(:plugin_id), :frozen?
    assert_predicate owned_diagnostic.fetch(:event), :frozen?

    (Mcweb::Plugins::Registry::MAX_DIAGNOSTICS + 5).times do |index|
      @registry.record_diagnostic(
        level: :warning,
        code: :bounded,
        phase: :runtime,
        message: "diagnostic-#{index}"
      )
    end
    @registry.record_diagnostic(
      level: :warning,
      code: :bounded,
      phase: :runtime,
      message: "x" * (Mcweb::Plugins::Registry::MAX_DIAGNOSTIC_MESSAGE_LENGTH + 10)
    )

    diagnostics = @registry.diagnostics
    assert_equal Mcweb::Plugins::Registry::MAX_DIAGNOSTICS, diagnostics.length
    assert_equal "diagnostic-6", diagnostics.first.fetch(:message)
    assert_equal Mcweb::Plugins::Registry::MAX_DIAGNOSTIC_MESSAGE_LENGTH,
                 diagnostics.last.fetch(:message).length
    assert_predicate diagnostics.last, :frozen?
    assert_raises(FrozenError) { diagnostics.last[:message] << "changed" }
  end

  test "duplicate concurrent registration executes only one definition block" do
    hits = 0
    hits_mutex = Mutex.new
    errors = Queue.new

    threads = 2.times.map do
      Thread.new do
        @registry.register(base_manifest(id: "acme/reserved")) do
          hits_mutex.synchronize { hits += 1 }
          sleep(0.01)
        end
      rescue Mcweb::Plugins::DuplicatePluginError => e
        errors << e
      end
    end
    threads.each(&:value)

    assert_equal 1, hits
    assert_equal 1, errors.length
    assert_equal [ "acme/reserved" ], @registry.ids
  end

  private

  def base_manifest(overrides = {})
    {
      id: "acme/demo",
      name: "Demo",
      version: "1.0.0",
      api_version: "1",
      requires: {},
      capabilities: [ "forum.events.read" ]
    }.merge(overrides)
  end

  def register(id, version: "1.0.0", requires: {}, capabilities: [ "forum.events.read" ], &block)
    @registry.register(
      id:,
      name: id,
      version:,
      api_version: "1",
      requires:,
      capabilities:,
      &block
    )
  end

  def plugin(id)
    @registry.list.find { |entry| entry[:id] == id }
  end
end
