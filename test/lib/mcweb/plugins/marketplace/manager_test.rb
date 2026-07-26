# frozen_string_literal: true

require "test_helper"
require "digest"
require "mcweb/plugins/marketplace"
require "tmpdir"
require "zip"

class Mcweb::Plugins::Marketplace::ManagerTest < ActiveSupport::TestCase
  setup do
    @temporary = Pathname(Dir.mktmpdir("mcweb-marketplace-manager"))
    @root = @temporary.join("plugins")
    @state_root = @temporary.join("state")
    @manager = build_manager
  end

  teardown do
    FileUtils.remove_entry(@temporary) if @temporary&.exist?
  end

  test "uses the default marketplace state directory when none is supplied" do
    manager = Mcweb::Plugins::Marketplace::Manager.new(
      root: @root,
      reload_callback: -> { [] },
      runtime_catalog: -> { [] }
    )

    assert_equal Rails.root.join("storage/plugin_marketplace").expand_path, manager.state_root
  end

  test "install validates provenance and exposes a redacted observable receipt" do
    package = plugin_package
    result = install(
      package,
      source: "https://packages.example.test/acme/demo.zip?access_token=never-store"
    )

    assert_equal "install", result.action
    assert_equal "active", result.status
    assert_equal "1.0.0", result.version
    assert @root.join("acme/demo/mcweb_plugin.yml").file?
    assert_equal "https://packages.example.test/acme/demo.zip", result.source.fetch(:url)

    snapshot = @manager.status
    plugin = snapshot.fetch(:plugins).sole
    assert_equal "active", plugin.fetch(:status)
    assert_equal result.sha256, plugin.fetch(:sha256)
    serialized = snapshot.to_json
    refute_includes serialized, "never-store"
    refute_includes serialized, package.to_s
    assert_equal %w[started succeeded], snapshot.fetch(:operations).pluck("status")
  end

  test "install records integrity failures without touching the managed path" do
    package = plugin_package

    assert_raises(Mcweb::Plugins::Marketplace::IntegrityError) do
      @manager.install(
        package_path: package,
        source: "file:///reviewed/demo.zip",
        expected_sha256: "f" * 64
      )
    end

    refute @root.join("acme/demo").exist?
    operation = @manager.status.fetch(:operations).last
    assert_equal "failed", operation.fetch("status")
    assert_equal "Mcweb::Plugins::Marketplace::IntegrityError", operation.fetch("error_class")
  end

  test "receipt persistence failure rolls back runtime and filesystem activation" do
    @state_root.join("receipts/acme/demo.json").mkpath

    error = assert_raises(Mcweb::Plugins::Marketplace::LifecycleError) do
      install(plugin_package)
    end

    assert_includes error.message, "previous filesystem state restored"
    refute @root.join("acme/demo").exist?
    assert_empty catalog_from_disk
    assert @state_root.glob("failed/**/acme/demo/mcweb_plugin.yml").any?
  end

  test "install rejects incompatible package metadata before activation" do
    package = plugin_package(
      metadata: {
        "schema_version" => "1",
        "plugin" => { "id" => "acme/demo", "version" => "1.0.0" },
        "compatibility" => { "ruby" => ">= 99.0" }
      }
    )

    assert_raises(Mcweb::Plugins::Marketplace::CompatibilityError) { install(package) }
    refute @root.join("acme/demo").exist?
  end

  test "upgrade is atomic and restores the prior version when runtime reload fails" do
    install(plugin_package(version: "1.0.0", body: "VERSION = 'one'\n"))
    broken = plugin_package(version: "2.0.0", body: "BROKEN\n")

    error = assert_raises(Mcweb::Plugins::Marketplace::LifecycleError) { install(broken) }

    assert_includes error.message, "previous filesystem state restored"
    manifest = Mcweb::Plugins::Manifest.load_file(@root.join("acme/demo/mcweb_plugin.yml"))
    assert_equal "1.0.0", manifest.version
    assert_equal "VERSION = 'one'\n", @root.join("acme/demo/plugin.rb").read
    assert @state_root.glob("failed/**/acme/demo/plugin.rb").any?
    assert_equal "failed", @manager.status.fetch(:operations).last.fetch("status")
  end

  test "upgrade enforces reverse dependency compatibility and downgrade intent" do
    install(plugin_package(id: "base/core", version: "1.5.0"))
    install(
      plugin_package(
        id: "addon/feature",
        requires: { "base/core" => "~> 1.0" }
      )
    )

    assert_raises(Mcweb::Plugins::Marketplace::DependencyError) do
      install(plugin_package(id: "base/core", version: "2.0.0"))
    end
    @manager.disable(plugin_id: "addon/feature")
    assert_raises(Mcweb::Plugins::Marketplace::DependencyError) do
      install(plugin_package(id: "base/core", version: "2.0.0"))
    end
    assert_equal "1.5.0",
                 Mcweb::Plugins::Manifest.load_file(@root.join("base/core/mcweb_plugin.yml")).version

    assert_raises(Mcweb::Plugins::Marketplace::CompatibilityError) do
      install(plugin_package(id: "base/core", version: "1.0.0"))
    end
  end

  test "install requires dependencies to be installed compatible and active" do
    addon = plugin_package(
      id: "addon/feature",
      requires: { "base/core" => ">= 1.0.0" }
    )

    assert_raises(Mcweb::Plugins::Marketplace::DependencyError) { install(addon) }

    install(plugin_package(id: "base/core", version: "1.0.0"))
    assert_equal "active", install(addon).status
  end

  test "disable enable and uninstall use recoverable moves" do
    install(plugin_package)

    disabled = @manager.disable(plugin_id: "acme/demo")
    assert_equal "disabled", disabled.status
    refute @root.join("acme/demo").exist?
    assert @state_root.join("disabled/acme/demo").directory?

    enabled = @manager.enable(plugin_id: "acme/demo")
    assert_equal "active", enabled.status
    assert @root.join("acme/demo").directory?
    refute @state_root.join("disabled/acme/demo").exist?

    uninstalled = uninstall
    assert_equal "uninstalled", uninstalled.status
    refute @root.join("acme/demo").exist?
    recovery = @state_root.join(uninstalled.recovery_path)
    assert recovery.join("mcweb_plugin.yml").file?
    assert_equal "uninstalled", @manager.status.fetch(:plugins).sole.fetch(:status)
  end

  test "dependants prevent unsafe disable and uninstall" do
    install(plugin_package(id: "base/core"))
    install(plugin_package(id: "addon/feature", requires: { "base/core" => ">= 1.0.0" }))

    assert_raises(Mcweb::Plugins::Marketplace::DependencyError) do
      @manager.disable(plugin_id: "base/core")
    end
    assert_raises(Mcweb::Plugins::Marketplace::DependencyError) do
      uninstall(plugin_id: "base/core")
    end
    assert @root.join("base/core").directory?
  end

  test "uninstall rejects a stale confirmed package identity without moving the current version" do
    install(plugin_package(version: "1.0.0"))
    confirmed = @manager.status.fetch(:plugins).sole
    install(plugin_package(version: "2.0.0"))

    error = assert_raises(Mcweb::Plugins::Marketplace::IntegrityError) do
      uninstall(
        expected_version: confirmed.fetch(:version),
        expected_sha256: confirmed.fetch(:sha256)
      )
    end

    assert_includes error.message, "refresh the plugin list"
    manifest = Mcweb::Plugins::Manifest.load_file(@root.join("acme/demo/mcweb_plugin.yml"))
    assert_equal "2.0.0", manifest.version
    assert_equal "active", @manager.status.fetch(:plugins).sole.fetch(:status)
    refute @state_root.glob("quarantine/**/acme/demo").any?
  end

  test "install refuses to overwrite unrelated files at the managed target" do
    occupied = @root.join("acme/demo")
    occupied.mkpath
    occupied.join("keep.txt").write("owned by operator")

    assert_raises(Mcweb::Plugins::Marketplace::LifecycleError) do
      install(plugin_package)
    end

    assert_equal "owned by operator", occupied.join("keep.txt").read
    refute occupied.join("mcweb_plugin.yml").exist?
  end

  test "install rejects plugin IDs that map to Windows device paths" do
    error = assert_raises(Mcweb::Plugins::Marketplace::LifecycleError) do
      install(plugin_package(id: "nul/example"))
    end

    assert_includes error.message, "not portable"
    refute @root.join("nul/example").exist?
  end

  test "lifecycle refuses deployment plugins outside the canonical managed path" do
    unmanaged = @root.join("operator-layout")
    unmanaged.mkpath
    unmanaged.join("mcweb_plugin.yml").write(
      {
        "id" => "acme/demo",
        "name" => "Demo",
        "version" => "1.0.0",
        "api_version" => "1",
        "entrypoint" => "plugin.rb"
      }.to_yaml
    )
    unmanaged.join("plugin.rb").write("PLUGIN = true\n")

    error = assert_raises(Mcweb::Plugins::Marketplace::LifecycleError) do
      @manager.uninstall(
        plugin_id: "acme/demo",
        expected_version: "1.0.0",
        expected_sha256: "a" * 64
      )
    end

    assert_includes error.message, "outside its managed"
    assert unmanaged.join("mcweb_plugin.yml").file?
  end

  test "allow_downgrade must be explicit and preserves the replaced version" do
    install(plugin_package(version: "2.0.0"))
    old = plugin_package(version: "1.0.0")

    assert_raises(Mcweb::Plugins::Marketplace::CompatibilityError) { install(old) }
    result = install(old, allow_downgrade: true)

    assert_equal "upgrade", result.action
    assert_equal "1.0.0", result.version
    assert result.recovery_path
    assert @state_root.join(result.recovery_path, "mcweb_plugin.yml").file?
  end

  test "concurrent installs serialize and never replace the same version twice" do
    package = plugin_package
    outcomes = Queue.new
    threads = 2.times.map do
      Thread.new do
        outcomes << install(package)
      rescue StandardError => e
        outcomes << e
      end
    end
    threads.each(&:join)
    values = 2.times.map { outcomes.pop }

    assert_equal 1, values.count { |value| value.is_a?(Mcweb::Plugins::Marketplace::Manager::Result) }
    assert_equal 1, values.count { |value| value.is_a?(Mcweb::Plugins::Marketplace::CompatibilityError) }
    assert_equal "1.0.0",
                 Mcweb::Plugins::Manifest.load_file(@root.join("acme/demo/mcweb_plugin.yml")).version
  end

  private

  def build_manager
    catalog = -> { catalog_from_disk }
    reload_callback = lambda do
      raise "simulated plugin load failure" if @root.glob("**/plugin.rb").any? { |path| path.read.include?("BROKEN") }

      catalog.call
    end

    Mcweb::Plugins::Marketplace::Manager.new(
      root: @root,
      state_root: @state_root,
      reload_callback: reload_callback,
      runtime_catalog: catalog,
      ruby_version: "4.0.6",
      rails_version: "8.1.2"
    )
  end

  def catalog_from_disk
    @root.glob("**/mcweb_plugin.yml").filter_map do |path|
      next if path.dirname.join("plugin.rb").read.include?("BROKEN")

      manifest = Mcweb::Plugins::Manifest.load_file(path)
      { id: manifest.id, status: "active" }
    end
  end

  def install(package, source: nil, allow_downgrade: false)
    @manager.install(
      package_path: package,
      source: source || "file:///reviewed/#{package.basename}",
      expected_sha256: Digest::SHA256.file(package).hexdigest,
      allow_downgrade: allow_downgrade
    )
  end

  def uninstall(plugin_id: "acme/demo", expected_version: nil, expected_sha256: nil)
    plugin = @manager.status(plugin_id: plugin_id).fetch(:plugins).sole
    @manager.uninstall(
      plugin_id:,
      expected_version: expected_version || plugin.fetch(:version),
      expected_sha256: expected_sha256 || plugin.fetch(:sha256)
    )
  end

  def plugin_package(id: "acme/demo", version: "1.0.0", requires: {}, body: "PLUGIN = true\n", metadata: nil)
    path = @temporary.join("#{id.tr('/', '-')}-#{version}-#{SecureRandom.hex(4)}.zip")
    manifest = {
      "id" => id,
      "name" => id,
      "version" => version,
      "api_version" => "1",
      "requires" => requires,
      "entrypoint" => "plugin.rb"
    }
    Zip::File.open(path, create: true) do |archive|
      archive.get_output_stream("mcweb_plugin.yml") { |stream| stream.write(manifest.to_yaml) }
      archive.get_output_stream("plugin.rb") { |stream| stream.write(body) }
      if metadata
        archive.get_output_stream("mcweb_package.yml") { |stream| stream.write(metadata.to_yaml) }
      end
    end
    path
  end
end
