# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/loader"
require "tmpdir"

class Mcweb::Plugins::LoaderTest < ActiveSupport::TestCase
  setup do
    Mcweb::Plugins.reset!
    @root = Pathname(Dir.mktmpdir("mcweb-plugin-sdk"))
    @previous_disable_plugins = ENV["MCWEB_DISABLE_PLUGINS"]
    ENV.delete("MCWEB_DISABLE_PLUGINS")
    $mcweb_plugin_sdk_hits = []
    $mcweb_plugin_sdk_outside_executed = false
    $mcweb_plugin_sdk_load_order = []
  end

  teardown do
    Mcweb::Plugins.reset!
    FileUtils.remove_entry(@root) if @root&.exist?
    if @previous_disable_plugins.nil?
      ENV.delete("MCWEB_DISABLE_PLUGINS")
    else
      ENV["MCWEB_DISABLE_PLUGINS"] = @previous_disable_plugins
    end
    $mcweb_plugin_sdk_hits = nil
    $mcweb_plugin_sdk_outside_executed = nil
    $mcweb_plugin_sdk_load_order = nil
  end

  test "reload discovers trusted manifests and does not duplicate subscriptions" do
    write_plugin(
      "acme-demo",
      manifest: manifest_yaml(id: "acme/demo"),
      entrypoint: <<~RUBY
        Mcweb::Plugins.register do |plugin|
          plugin.on("forum.plugin.loaded", priority: 10) do |event|
            $mcweb_plugin_sdk_hits << event.event_id
          end
        end
      RUBY
    )

    Mcweb::Plugins.reload!(root: @root)
    Mcweb::Events.publish("forum.plugin.loaded")
    assert_equal 1, $mcweb_plugin_sdk_hits.length
    assert_equal "active", Mcweb::Plugins.list.first.fetch(:status)

    Mcweb::Plugins.reload!(root: @root)
    Mcweb::Events.publish("forum.plugin.loaded")
    assert_equal 2, $mcweb_plugin_sdk_hits.length
    assert_equal 1, Mcweb::Plugins.list.length
  end

  test "reload if changed skips unchanged entrypoints and reloads source changes" do
    plugin_dir = write_plugin(
      "changed-only",
      manifest: manifest_yaml(id: "reload/changed-only"),
      entrypoint: <<~RUBY
        $mcweb_plugin_sdk_load_order << "version-one"
        Mcweb::Plugins.register
      RUBY
    )

    Mcweb::Plugins.reload_if_changed!(root: @root)
    Mcweb::Plugins.reload_if_changed!(root: @root)
    assert_equal [ "version-one" ], $mcweb_plugin_sdk_load_order

    File.write(
      plugin_dir.join("plugin.rb"),
      <<~RUBY
        $mcweb_plugin_sdk_load_order << "version-two"
        Mcweb::Plugins.register
      RUBY
    )
    changed_at = (Time.current + 1.second).to_time
    File.utime(changed_at, changed_at, plugin_dir.join("plugin.rb"))
    Mcweb::Plugins.reload_if_changed!(root: @root)

    assert_equal [ "version-one", "version-two" ],
      $mcweb_plugin_sdk_load_order
  end

  test "entrypoint traversal is rejected before trusted code executes" do
    outside = @root.join("outside.rb")
    File.write(outside, "$mcweb_plugin_sdk_outside_executed = true\n")
    plugin_dir = @root.join("bad-plugin")
    FileUtils.mkdir_p(plugin_dir)
    File.write(
      plugin_dir.join("mcweb_plugin.yml"),
      manifest_yaml(id: "bad/traversal", entrypoint: "../outside.rb")
    )

    Mcweb::Plugins.reload!(root: @root)

    refute $mcweb_plugin_sdk_outside_executed
    assert_empty Mcweb::Plugins.list
    assert Mcweb::Plugins.diagnostics.any? { |entry| entry[:code] == "plugin_load_failed" }
  end

  test "dependency entrypoints load before dependants regardless of directory order" do
    write_plugin(
      "a-addon",
      manifest: manifest_yaml(id: "addon/feature", requires: { "base/core" => ">= 1.0.0" }),
      entrypoint: <<~RUBY
        raise "base entrypoint was not loaded first" unless $mcweb_plugin_sdk_load_order == ["base/core"]
        $mcweb_plugin_sdk_load_order << "addon/feature"
        Mcweb::Plugins.register
      RUBY
    )
    write_plugin(
      "z-base",
      manifest: manifest_yaml(id: "base/core"),
      entrypoint: <<~RUBY
        $mcweb_plugin_sdk_load_order << "base/core"
        Mcweb::Plugins.register
      RUBY
    )

    Mcweb::Plugins.reload!(root: @root)

    assert_equal %w[base/core addon/feature], $mcweb_plugin_sdk_load_order
    assert_equal %w[addon/feature base/core], Mcweb::Plugins.list.pluck(:id)
    assert_equal %w[active active], Mcweb::Plugins.list.pluck(:status)
    assert_empty Mcweb::Plugins.diagnostics.select { |entry| entry[:code] == "plugin_load_failed" }
  end

  test "a dependant entrypoint is not executed after a discovered dependency fails to load" do
    write_plugin(
      "a-addon",
      manifest: manifest_yaml(id: "addon/feature", requires: { "base/core" => ">= 1.0.0" }),
      entrypoint: <<~RUBY
        $mcweb_plugin_sdk_load_order << "addon/feature-side-effect"
        Mcweb::Plugins.register
      RUBY
    )
    write_plugin(
      "z-base",
      manifest: manifest_yaml(id: "base/core"),
      entrypoint: <<~RUBY
        $mcweb_plugin_sdk_load_order << "base/core-attempted"
        raise "base failed to load"
      RUBY
    )

    Mcweb::Plugins.reload!(root: @root)

    assert_equal [ "base/core-attempted" ], $mcweb_plugin_sdk_load_order
    assert_equal [ "addon/feature" ], Mcweb::Plugins.list.pluck(:id)
    assert_equal "disabled", Mcweb::Plugins.list.first.fetch(:status)
    diagnostic = Mcweb::Plugins.diagnostics.find do |entry|
      entry[:code] == "dependency_load_failed" && entry[:plugin_id] == "addon/feature"
    end
    assert diagnostic
    assert_includes diagnostic[:message], "base/core"
  end

  test "an undiscovered dependency keeps registration then boot disable semantics" do
    write_plugin(
      "missing-dependency",
      manifest: manifest_yaml(id: "addon/missing", requires: { "absent/core" => ">= 1.0.0" }),
      entrypoint: <<~RUBY
        $mcweb_plugin_sdk_load_order << "addon/missing-executed"
        Mcweb::Plugins.register
      RUBY
    )

    Mcweb::Plugins.reload!(root: @root)

    assert_equal [ "addon/missing-executed" ], $mcweb_plugin_sdk_load_order
    assert_equal "disabled", Mcweb::Plugins.list.first.fetch(:status)
    assert Mcweb::Plugins.diagnostics.any? { |entry| entry[:code] == "missing_dependency" }
    assert_not Mcweb::Plugins.diagnostics.any? { |entry| entry[:code] == "dependency_load_failed" }
  end

  test "a raising entrypoint rolls back every definition it registered" do
    write_plugin(
      "broken",
      manifest: manifest_yaml(id: "broken/plugin"),
      entrypoint: <<~RUBY
        Mcweb::Plugins.register { |plugin| plugin.on("forum.broken") { nil } }
        raise "entrypoint exploded"
      RUBY
    )

    Mcweb::Plugins.reload!(root: @root)

    assert_empty Mcweb::Plugins.list
    diagnostic = Mcweb::Plugins.diagnostics.find { |entry| entry[:code] == "plugin_load_failed" }
    assert diagnostic
    assert_includes diagnostic[:message], "entrypoint exploded"
  end

  test "safe YAML rejects object deserialization" do
    plugin_dir = @root.join("unsafe")
    FileUtils.mkdir_p(plugin_dir)
    File.write(plugin_dir.join("mcweb_plugin.yml"), "--- !ruby/object:Object {}\n")
    File.write(plugin_dir.join("plugin.rb"), "$mcweb_plugin_sdk_outside_executed = true\n")

    Mcweb::Plugins.reload!(root: @root)

    refute $mcweb_plugin_sdk_outside_executed
    assert_empty Mcweb::Plugins.list
    assert Mcweb::Plugins.diagnostics.any? { |entry| entry[:message].include?("invalid safe YAML") }
  end

  test "disable switch skips manifest entrypoints" do
    write_plugin(
      "disabled",
      manifest: manifest_yaml(id: "disabled/plugin"),
      entrypoint: "$mcweb_plugin_sdk_outside_executed = true\n"
    )
    ENV["MCWEB_DISABLE_PLUGINS"] = "1"

    Mcweb::Plugins.reload!(root: @root)

    refute $mcweb_plugin_sdk_outside_executed
    assert_empty Mcweb::Plugins.list
    assert Mcweb::Plugins.diagnostics.any? { |entry| entry[:code] == "plugins_disabled" }
  end

  test "known dependency version mismatches skip dependant entrypoint side effects" do
    write_plugin(
      "a-addon",
      manifest: manifest_yaml(id: "addon/versioned", requires: { "base/core" => ">= 2.0.0" }),
      entrypoint: <<~RUBY
        $mcweb_plugin_sdk_load_order << "addon/versioned-side-effect"
        Mcweb::Plugins.register
      RUBY
    )
    write_plugin(
      "z-base",
      manifest: manifest_yaml(id: "base/core"),
      entrypoint: <<~RUBY
        $mcweb_plugin_sdk_load_order << "base/core"
        Mcweb::Plugins.register
      RUBY
    )

    Mcweb::Plugins.reload!(root: @root)

    assert_equal [ "base/core" ], $mcweb_plugin_sdk_load_order
    assert_equal "disabled", Mcweb::Plugins.list.find { |plugin| plugin[:id] == "addon/versioned" }.fetch(:status)
    assert Mcweb::Plugins.diagnostics.any? do |entry|
      entry[:phase] == "load" &&
        entry[:code] == "dependency_version_mismatch" &&
        entry[:plugin_id] == "addon/versioned"
    end
  end

  test "dependency cycle entrypoints remain inert before activation" do
    write_plugin(
      "cycle-one",
      manifest: manifest_yaml(id: "cycle/one", requires: { "cycle/two" => ">= 1.0.0" }),
      entrypoint: <<~RUBY
        $mcweb_plugin_sdk_load_order << "cycle/one-side-effect"
        Mcweb::Plugins.register
      RUBY
    )
    write_plugin(
      "cycle-two",
      manifest: manifest_yaml(id: "cycle/two", requires: { "cycle/one" => ">= 1.0.0" }),
      entrypoint: <<~RUBY
        $mcweb_plugin_sdk_load_order << "cycle/two-side-effect"
        Mcweb::Plugins.register
      RUBY
    )

    Mcweb::Plugins.reload!(root: @root)

    assert_empty $mcweb_plugin_sdk_load_order
    assert_equal %w[disabled disabled], Mcweb::Plugins.list.pluck(:status)
    cycle_diagnostics = Mcweb::Plugins.diagnostics.count do |entry|
      entry[:phase] == "load" && entry[:code] == "dependency_cycle"
    end
    assert_equal 2, cycle_diagnostics
  end

  test "duplicate discovered ids reject every entrypoint before execution" do
    write_plugin(
      "duplicate-one",
      manifest: manifest_yaml(id: "duplicate/plugin"),
      entrypoint: "$mcweb_plugin_sdk_load_order << 'duplicate-one-side-effect'\nMcweb::Plugins.register\n"
    )
    write_plugin(
      "duplicate-two",
      manifest: manifest_yaml(id: "duplicate/plugin"),
      entrypoint: "$mcweb_plugin_sdk_load_order << 'duplicate-two-side-effect'\nMcweb::Plugins.register\n"
    )

    Mcweb::Plugins.reload!(root: @root)

    assert_empty $mcweb_plugin_sdk_load_order
    assert_empty Mcweb::Plugins.list
    duplicate_diagnostics = Mcweb::Plugins.diagnostics.count do |entry|
      entry[:code] == "duplicate_plugin_manifest"
    end
    assert_equal 2, duplicate_diagnostics
  end

  test "duplicate YAML mapping keys are rejected before entrypoint execution" do
    plugin_dir = @root.join("duplicate-yaml")
    FileUtils.mkdir_p(plugin_dir)
    File.write(
      plugin_dir.join("mcweb_plugin.yml"),
      <<~YAML
        id: duplicate/yaml
        name: Duplicate YAML
        version: 1.0.0
        version: 2.0.0
        api_version: "1"
      YAML
    )
    File.write(plugin_dir.join("plugin.rb"), "$mcweb_plugin_sdk_outside_executed = true\n")

    Mcweb::Plugins.reload!(root: @root)

    refute $mcweb_plugin_sdk_outside_executed
    assert_empty Mcweb::Plugins.list
    assert Mcweb::Plugins.diagnostics.any? do |entry|
      entry[:message].include?("duplicate manifest key")
    end
  end

  test "invalid permission contributions are rejected before entrypoint execution" do
    plugin_dir = @root.join("invalid-permission-contribution")
    FileUtils.mkdir_p(plugin_dir.join("config"))
    File.write(
      plugin_dir.join("mcweb_plugin.yml"),
      {
        "id" => "acme/permissions",
        "name" => "Invalid permissions",
        "version" => "1.0.0",
        "api_version" => "1",
        "entrypoint" => "plugin.rb",
        "contributions" => {
          "permissions" => "config/permissions.yml"
        }
      }.to_yaml
    )
    File.write(
      plugin_dir.join("config/permissions.yml"),
      {
        "permissions" => [
          {
            "id" => "other/plugin.orders.view",
            "group" => "acme.permissions.orders",
            "title_phrase" => "permission.orders_view.title",
            "description_phrase" => "permission.orders_view.description",
            "scope" => "global",
            "default" => "none"
          }
        ]
      }.to_yaml
    )
    File.write(
      plugin_dir.join("plugin.rb"),
      "$mcweb_plugin_sdk_outside_executed = true\nMcweb::Plugins.register\n"
    )

    Mcweb::Plugins.reload!(root: @root)

    refute $mcweb_plugin_sdk_outside_executed
    assert_empty Mcweb::Plugins.list
    assert Mcweb::Plugins.diagnostics.any? do |entry|
      entry[:code] == "plugin_load_failed" &&
        entry[:message].include?("permission contribution id")
    end
  end

  test "concurrent reloads leave one active generation and one subscription" do
    write_plugin(
      "concurrent-reload",
      manifest: manifest_yaml(id: "reload/concurrent"),
      entrypoint: <<~RUBY
        Mcweb::Plugins.register do |plugin|
          plugin.on("forum.concurrent.reload") do |event|
            $mcweb_plugin_sdk_hits << event.event_id
          end
        end
      RUBY
    )

    threads = 6.times.map do
      Thread.new { Mcweb::Plugins.reload!(root: @root) }
    end
    threads.each(&:value)
    Mcweb::Events.publish("forum.concurrent.reload")

    assert_equal 1, $mcweb_plugin_sdk_hits.length
    assert_equal [ "reload/concurrent" ], Mcweb::Plugins.list.pluck(:id)
    assert_equal "active", Mcweb::Plugins.list.first.fetch(:status)
  end

  test "plugin roots containing glob metacharacters are discovered literally" do
    special_root = @root.join("plugins[development]")
    plugin_dir = special_root.join("literal-root")
    FileUtils.mkdir_p(plugin_dir)
    File.write(
      plugin_dir.join("mcweb_plugin.yml"),
      manifest_yaml(id: "path/literal")
    )
    File.write(
      plugin_dir.join("plugin.rb"),
      "$mcweb_plugin_sdk_load_order << 'path/literal'\nMcweb::Plugins.register\n"
    )

    Mcweb::Plugins.reload!(root: special_root)

    assert_equal [ "path/literal" ], $mcweb_plugin_sdk_load_order
    assert_equal [ "path/literal" ], Mcweb::Plugins.list.pluck(:id)
  end

  private

  def write_plugin(directory, manifest:, entrypoint:)
    plugin_dir = @root.join(directory)
    FileUtils.mkdir_p(plugin_dir)
    File.write(plugin_dir.join("mcweb_plugin.yml"), manifest)
    File.write(plugin_dir.join("plugin.rb"), entrypoint)
    plugin_dir
  end

  def manifest_yaml(id:, entrypoint: "plugin.rb", requires: {})
    {
      "id" => id,
      "name" => id,
      "version" => "1.0.0",
      "api_version" => "1",
      "entrypoint" => entrypoint,
      "requires" => requires,
      "capabilities" => [ "forum.events.read" ]
    }.to_yaml
  end
end
