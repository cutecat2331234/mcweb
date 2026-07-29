# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/loader"
require "tmpdir"

class Mcweb::Plugins::ContributionRegistryTest < ActiveSupport::TestCase
  class FakeEventBus
    Handle = Data.define(:event, :callback)

    def initialize
      @listeners = Hash.new { |hash, key| hash[key] = [] }
    end

    def subscribe(event, &callback)
      Handle.new(event:, callback:).tap { |handle| @listeners[event] << handle }
    end

    def unsubscribe(handle)
      @listeners[handle.event].delete(handle)
    end

    def publish(event, payload = {})
      @listeners[event].dup.each { |handle| handle.callback.call(payload) }
    end
  end

  setup do
    @temporary = Pathname(Dir.mktmpdir("mcweb-contributions"))
    @registry = Mcweb::Plugins::Registry.new(
      event_bus: FakeEventBus.new,
      logger: Logger.new(IO::NULL)
    )
  end

  teardown do
    @registry.reset!
    FileUtils.remove_entry(@temporary) if @temporary&.exist?
  end

  test "loads every stable contribution kind as immutable descriptors" do
    manifest = plugin_manifest(
      id: "acme/demo",
      contributions: [
        contribution(
          "navigation",
          "nav.main",
          payload: {
            "surface" => "admin",
            "position" => "sidebar",
            "label_phrase" => "acme.demo.nav.label",
            "href" => "/plugins/acme/demo/overview"
          }
        ),
        contribution(
          "page",
          "page.overview",
          payload: {
            "surface" => "admin",
            "path" => "/admin/plugins/acme/demo/overview",
            "title_phrase" => "acme.demo.page.title",
            "blocks" => [ { "type" => "notice", "phrase" => "acme.demo.page.notice" } ]
          }
        ),
        contribution(
          "ui_slot",
          "slot.dashboard",
          payload: {
            "slot" => "dashboard.cards",
            "kind" => "card",
            "title_phrase" => "acme.demo.dashboard.title"
          }
        ),
        contribution(
          "translation",
          "translation.zh_cn",
          payload: {
            "locale" => "zh-CN",
            "phrases" => { "acme.demo.nav.label" => "示例插件" }
          }
        ),
        contribution(
          "event",
          "event.completed",
          payload: {
            "name" => "acme.demo.completed",
            "direction" => "emits",
            "schema_version" => "1",
            "description_phrase" => "acme.demo.events.completed"
          }
        ),
        contribution(
          "entity_metadata",
          "metadata.topic",
          payload: {
            "entity" => "forum.topic",
            "fields" => {
              "acme.demo.score" => { "type" => "integer" }
            }
          }
        )
      ]
    )

    entries = Mcweb::Plugins::ContributionDocumentLoader.load(manifest)

    assert_equal %w[entity_metadata event navigation page translation ui_slot],
                 entries.map(&:type).sort
    assert entries.all?(&:frozen?)
    assert entries.all? { |entry| entry.payload.frozen? }
    assert_equal "admin", entries.find { |entry| entry.type == "navigation" }.payload.fetch("surface")
  end

  test "catalog orders priorities and before after relations deterministically" do
    catalog = Mcweb::Plugins::ContributionCatalog.new
    base = build_contribution(
      plugin_id: "base/core",
      id: "base.core.nav.main",
      priority: 100
    )
    addon = build_contribution(
      plugin_id: "addon/tools",
      id: "addon.tools.nav.main",
      priority: 10,
      after: [ base.id ]
    )
    footer = build_contribution(
      plugin_id: "footer/links",
      id: "footer.links.nav.main",
      priority: 500,
      before: [ base.id ]
    )

    assert_empty catalog.activate([ base ])
    assert_empty catalog.activate([ addon ])
    assert_empty catalog.activate([ footer ])

    assert_equal [ footer.id, base.id, addon.id ], catalog.all.map(&:id)
    assert_equal [ addon.id ], catalog.for_plugin("addon/tools").map(&:id)
  end

  test "missing requirements explicit conflicts and ordering cycles are atomic and diagnosable" do
    catalog = Mcweb::Plugins::ContributionCatalog.new
    base = build_contribution(plugin_id: "base/core", id: "base.core.nav.main")
    assert_empty catalog.activate([ base ])

    missing = build_contribution(
      plugin_id: "addon/tools",
      id: "addon.tools.nav.missing",
      requires: [ "vendor.absent.nav.item" ]
    )
    conflict = catalog.activate([ missing ]).sole
    assert_equal "missing_required_contribution", conflict.code
    assert_includes conflict.recommendation, "vendor.absent.nav.item"
    assert_nil catalog.find(missing.id)

    explicit = build_contribution(
      plugin_id: "addon/tools",
      id: "addon.tools.nav.conflict",
      conflicts: [ base.id ]
    )
    conflict = catalog.activate([ explicit ]).sole
    assert_equal "explicit_conflict", conflict.code
    assert_equal "base/core", conflict.other_plugin_id
    assert_nil catalog.find(explicit.id)

    first = build_contribution(
      plugin_id: "cycle/one",
      id: "cycle.one.nav.main",
      before: [ "cycle.two.nav.main" ]
    )
    second = build_contribution(
      plugin_id: "cycle/two",
      id: "cycle.two.nav.main",
      before: [ first.id ]
    )
    assert_empty catalog.activate([ first ])
    cycles = catalog.activate([ second ])
    assert cycles.all? { |entry| entry.code == "ordering_cycle" }
    assert_nil catalog.find(second.id)
  end

  test "registry atomically activates contributions and removes them on unregister" do
    manifest = plugin_manifest(
      id: "acme/demo",
      contributions: [
        contribution(
          "navigation",
          "nav.main",
          payload: {
            "surface" => "public",
            "position" => "header",
            "label_phrase" => "acme.demo.nav.label",
            "href" => "/plugins/acme/demo/overview"
          }
        )
      ]
    )

    @registry.register(manifest)
    @registry.boot!

    assert_equal "active", @registry.list.sole.fetch(:status)
    descriptor = @registry.contributions(type: "navigation").sole
    assert_equal "acme.demo.nav.main", descriptor.fetch(:id)
    assert_equal descriptor, @registry.contributions_for("acme/demo").sole

    @registry.unregister("acme/demo")
    assert_empty @registry.contributions
  end

  test "registry disables a plugin with an actionable cross-plugin conflict" do
    base = plugin_manifest(
      id: "base/core",
      contributions: [
        contribution(
          "navigation",
          "nav.main",
          namespace: "base.core",
          payload: {
            "surface" => "admin",
            "position" => "sidebar",
            "label_phrase" => "base.core.nav.label",
            "href" => "/plugins/base/core/overview"
          }
        )
      ]
    )
    addon = plugin_manifest(
      id: "addon/tools",
      requires: { "base/core" => ">= 1.0.0" },
      contributions: [
        contribution(
          "navigation",
          "nav.main",
          namespace: "addon.tools",
          conflicts: [ "base.core.nav.main" ],
          payload: {
            "surface" => "admin",
            "position" => "sidebar",
            "label_phrase" => "addon.tools.nav.label",
            "href" => "/plugins/addon/tools/overview"
          }
        )
      ]
    )

    @registry.register(base)
    @registry.register(addon)
    @registry.boot!

    assert_equal "active", @registry.list.find { |entry| entry[:id] == "base/core" }.fetch(:status)
    addon_state = @registry.list.find { |entry| entry[:id] == "addon/tools" }
    assert_equal "disabled", addon_state.fetch(:status)
    diagnostic = @registry.diagnostics.find { |entry| entry[:plugin_id] == "addon/tools" }
    assert_equal "contribution_explicit_conflict", diagnostic.fetch(:code)
    assert_includes diagnostic.fetch(:message), "disable one contribution"
  end

  private

  def plugin_manifest(id:, contributions:, requires: {})
    directory = @temporary.join(id.tr("/", "-"))
    directory.mkpath
    manifest_path = directory.join("mcweb_plugin.yml")
    catalog_path = directory.join("config/contributions.yml")
    catalog_path.dirname.mkpath
    catalog_path.write(
      {
        "schema_version" => "1",
        "contributions" => contributions
      }.to_yaml
    )
    attributes = {
      "id" => id,
      "name" => id,
      "version" => "1.0.0",
      "api_version" => "1",
      "requires" => requires,
      "contributions" => { "catalog" => "config/contributions.yml" }
    }
    manifest_path.write(attributes.to_yaml)
    Mcweb::Plugins::Manifest.load_file(manifest_path)
  end

  def contribution(type, suffix, payload:, **relations)
    {
      "type" => type,
      "id" => relations.delete(:id) || "#{relations.delete(:namespace) || 'acme.demo'}.#{suffix}",
      "payload" => payload
    }.merge(relations.transform_keys(&:to_s))
  end

  def build_contribution(plugin_id:, id:, priority: 100, before: [], after: [], requires: [], conflicts: [])
    namespace = plugin_id.tr("/-", "._")
    Mcweb::Plugins::Contribution.new(
      plugin_id:,
      source: "/reviewed/contributions.yml",
      attributes: {
        "type" => "navigation",
        "id" => id,
        "priority" => priority,
        "before" => before,
        "after" => after,
        "requires" => requires,
        "conflicts" => conflicts,
        "payload" => {
          "surface" => "admin",
          "position" => "sidebar",
          "label_phrase" => "#{namespace}.nav.label",
          "href" => "/plugins/#{plugin_id}/overview"
        }
      }
    )
  end
end
