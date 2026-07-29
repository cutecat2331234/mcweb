# frozen_string_literal: true

require "digest"
require "json"
require "stringio"
require "test_helper"
require "mcweb/plugins/devtools"
require "tmpdir"

class Mcweb::Plugins::DevtoolsTest < ActiveSupport::TestCase
  setup do
    @temporary = Pathname(Dir.mktmpdir("mcweb-plugin-devtools"))
    Mcweb::Plugins.reset!
  end

  teardown do
    Mcweb::Plugins.reset!
    FileUtils.remove_entry(@temporary) if @temporary&.exist?
  end

  test "create generates a complete scaffold accepted by validate and JSON CLI" do
    created = Mcweb::Plugins::Devtools::Creator.new(
      plugin_id: "testing/generated",
      root: @temporary,
      name: "Generated Plugin",
      author: "McWeb Test"
    ).call

    assert_predicate created, :ok?, created.errors.inspect
    plugin_root = Pathname(created.data.fetch("path"))
    %w[
      CHANGELOG.md README.md config/contributions.yml config/settings.yml
      locales/en.yml locales/zh-CN.yml mcweb_plugin.yml plugin.rb test/contract_test.rb
    ].each { |path| assert plugin_root.join(path).file?, path }
    assert_predicate(
      Mcweb::Plugins::Devtools::Validator.new(path: plugin_root).call,
      :ok?
    )

    output = StringIO.new
    status = Mcweb::Plugins::Devtools::Command.run(
      [ "validate", plugin_root.to_s, "--json" ],
      out: output,
      err: StringIO.new
    )
    assert_equal 0, status
    assert JSON.parse(output.string).fetch("ok")
  end

  test "build is reproducible and produces a package accepted by the marketplace archive" do
    source = reference_plugin("hello-event")
    first = Mcweb::Plugins::Devtools::Builder.new(
      path: source,
      output: @temporary.join("first")
    ).call
    second = Mcweb::Plugins::Devtools::Builder.new(
      path: source,
      output: @temporary.join("second")
    ).call

    assert_predicate first, :ok?, first.errors.inspect
    assert_predicate second, :ok?, second.errors.inspect
    assert_equal first.data.fetch("sha256"), second.data.fetch("sha256")

    artifact = Pathname(first.data.fetch("artifact"))
    extracted = @temporary.join("extracted")
    Mcweb::Plugins::Marketplace::PackageArchive.new(
      path: artifact,
      source: "file:///reference/hello-event.zip",
      expected_sha256: Digest::SHA256.file(artifact).hexdigest
    ).extract_to(extracted)
    assert extracted.join("files.sha256").file?
    assert extracted.join("mcweb_package.yml").file?
    assert_predicate(
      Mcweb::Plugins::Devtools::Validator.new(path: extracted).call,
      :ok?
    )
  end

  test "release and source health expose stable machine-readable contracts" do
    source = reference_plugin("forum-extension")
    release = Mcweb::Plugins::Devtools::Releaser.new(
      path: source,
      output: @temporary.join("release")
    ).call
    health = Mcweb::Plugins::Devtools::HealthChecker.new(target: source).call

    assert_predicate release, :ok?, release.errors.inspect
    assert Pathname(release.data.fetch("release_manifest")).file?
    assert Pathname(release.data.fetch("release_notes")).file?
    assert_predicate health, :ok?, health.errors.inspect
    assert_equal "source", health.data.fetch("mode")
  end

  test "all reference plugins pass validation host activation and the CE realtime boundary" do
    %w[hello-event forum-extension commerce-fulfillment].each do |name|
      result = Mcweb::Plugins::Devtools::ContractTester.new(
        path: reference_plugin(name),
        test_executor: ->(_files) {
          { success: true, exit_status: 0, output: "" }
        }
      ).call

      assert_predicate result, :ok?, "#{name}: #{result.errors.inspect}"
      checks = result.data.fetch("contract_checks")
      assert_equal "passed", checks.find { |entry| entry["name"] == "host_lifecycle" }.fetch("status")
      assert_equal "passed", checks.find { |entry| entry["name"] == "ce_realtime_boundary" }.fetch("status")
    end
  end

  test "reference packages complete install disable enable and uninstall lifecycle" do
    plugin_root = @temporary.join("installed")
    state_root = @temporary.join("state")
    manager = Mcweb::Plugins::Marketplace::Manager.new(
      root: plugin_root,
      state_root:,
      reload_callback: -> { Mcweb::Plugins.reload!(root: plugin_root) },
      runtime_catalog: -> { Mcweb::Plugins.list },
      generation_coordinator: nil
    )

    %w[hello-event forum-extension commerce-fulfillment].each do |name|
      build = Mcweb::Plugins::Devtools::Builder.new(
        path: reference_plugin(name),
        output: @temporary.join("packages")
      ).call
      assert_predicate build, :ok?, build.errors.inspect
      artifact = Pathname(build.data.fetch("artifact"))
      installed = manager.install(
        package_path: artifact,
        source: "file:///reference/#{artifact.basename}",
        expected_sha256: build.data.fetch("sha256")
      )
      manager.disable(plugin_id: installed.plugin_id)
      manager.enable(plugin_id: installed.plugin_id)
      manager.uninstall(
        plugin_id: installed.plugin_id,
        expected_version: installed.version,
        expected_sha256: installed.sha256
      )
    end
  end

  private

  def reference_plugin(name)
    Rails.root.join("examples/plugins", name)
  end
end
