# frozen_string_literal: true

require "test_helper"
require "digest"
require "mcweb/plugins/marketplace"
require "tmpdir"
require "zip"

class Mcweb::Plugins::Marketplace::SetupLifecycleTest < ActiveSupport::TestCase
  setup do
    @temporary = Pathname(Dir.mktmpdir("mcweb-marketplace-setup"))
    @root = @temporary.join("plugins")
    @state_root = @temporary.join("state")
    @manager = build_manager
    @setting_keys = []
    $mcweb_setup_lifecycle_hits = []
  end

  teardown do
    SiteSetting.where(key: @setting_keys).delete_all if @setting_keys.any?
    $mcweb_setup_lifecycle_hits = nil
    FileUtils.remove_entry(@temporary) if @temporary&.exist?
  end

  test "manifest setup path is an optional package-local Ruby file" do
    base = {
      id: "acme/demo",
      name: "Demo",
      version: "1.0.0",
      api_version: "1"
    }

    assert_nil Mcweb::Plugins::Manifest.from_hash(base).setup
    assert_equal "db/setup.rb", Mcweb::Plugins::Manifest.from_hash(base.merge(setup: "db/setup.rb")).setup
    assert_raises(Mcweb::Plugins::ManifestError) do
      Mcweb::Plugins::Manifest.from_hash(base.merge(setup: "../outside.rb"))
    end
    assert_raises(Mcweb::Plugins::ManifestError) do
      Mcweb::Plugins::Manifest.from_hash(base.merge(setup: "db/setup.yml"))
    end
  end

  test "install records ordered completed steps and disable enable do not execute hooks" do
    key = setting_key
    package = plugin_package(
      setup: <<~RUBY
        Mcweb::Plugins::Marketplace::Setup.define do
          install_step "create_setting" do
            SiteSetting.set(#{key.inspect}, { "installed" => true })
            $mcweb_setup_lifecycle_hits << "install"
          end

          teardown_step "remove_setting" do
            SiteSetting.unset(#{key.inspect})
            $mcweb_setup_lifecycle_hits << "uninstall"
          end
        end
      RUBY
    )

    result = install(package)

    assert_equal "install", result.action
    assert_equal({ "installed" => true }, SiteSetting.get(key))
    setup = @manager.status.fetch(:plugins).sole.fetch(:setup)
    assert_equal "1", setup.fetch("schema_version")
    assert_equal "1.0.0", setup.fetch("completed_version")
    assert_equal [ "create_setting" ], setup.fetch("completed_steps").pluck("id")

    @manager.disable(plugin_id: "acme/demo")
    @manager.enable(plugin_id: "acme/demo")
    assert_equal [ "install" ], $mcweb_setup_lifecycle_hits

    uninstall
    assert_nil SiteSetting.get(key)
    assert_equal %w[install uninstall], $mcweb_setup_lifecycle_hits
    completed = @manager.status.fetch(:plugins).sole.fetch(:setup).fetch("completed_steps")
    assert_equal %w[create_setting remove_setting], completed.pluck("id")
  end

  test "stale uninstall identity is rejected before the upgraded teardown can run" do
    install(
      plugin_package(
        version: "1.0.0",
        setup: <<~RUBY
          Mcweb::Plugins::Marketplace::Setup.define do
            uninstall_step("remove_v1") { $mcweb_setup_lifecycle_hits << "uninstall-v1" }
          end
        RUBY
      )
    )
    confirmed = @manager.status.fetch(:plugins).sole
    install(
      plugin_package(
        version: "2.0.0",
        setup: <<~RUBY
          Mcweb::Plugins::Marketplace::Setup.define do
            uninstall_step("remove_v2") { $mcweb_setup_lifecycle_hits << "uninstall-v2" }
          end
        RUBY
      )
    )

    assert_raises(Mcweb::Plugins::Marketplace::IntegrityError) do
      uninstall(
        expected_version: confirmed.fetch(:version),
        expected_sha256: confirmed.fetch(:sha256)
      )
    end

    assert_empty $mcweb_setup_lifecycle_hits
    assert_equal "2.0.0",
                 Mcweb::Plugins::Manifest.load_file(@root.join("acme/demo/mcweb_plugin.yml")).version
  end

  test "upgrade steps run by target version then declaration order" do
    install(
      plugin_package(
        version: "1.0.0",
        setup: <<~RUBY
          Mcweb::Plugins::Marketplace::Setup.define do
            install_step("install") { $mcweb_setup_lifecycle_hits << "install" }
          end
        RUBY
      )
    )
    upgrade = plugin_package(
      version: "2.0.0",
      setup: <<~RUBY
        Mcweb::Plugins::Marketplace::Setup.define do
          upgrade_step("upgrade_2", to: "2.0.0") { $mcweb_setup_lifecycle_hits << "2.0.0" }
          upgrade_step("upgrade_1_b", to: "1.5.0") { $mcweb_setup_lifecycle_hits << "1.5.0-b" }
          upgrade_step("upgrade_1_a", to: "1.5.0") { $mcweb_setup_lifecycle_hits << "1.5.0-a" }
        end
      RUBY
    )

    result = install(upgrade)

    assert_equal "upgrade", result.action
    assert_equal %w[install 1.5.0-b 1.5.0-a 2.0.0], $mcweb_setup_lifecycle_hits
    setup = @manager.status.fetch(:plugins).sole.fetch(:setup)
    assert_equal "2.0.0", setup.fetch("completed_version")
    assert_equal %w[install upgrade_1_b upgrade_1_a upgrade_2],
                 setup.fetch("completed_steps").pluck("id")
  end

  test "failed upgrade restores the previous database files runtime and setup receipt" do
    key = setting_key
    install(
      plugin_package(
        version: "1.0.0",
        setup: <<~RUBY
          Mcweb::Plugins::Marketplace::Setup.define do
            install_step("create_setting") { SiteSetting.set(#{key.inspect}, { "version" => 1 }) }
          end
        RUBY
      )
    )
    receipt_before = @state_root.join("receipts/acme/demo.json").binread
    upgrade = plugin_package(
      version: "2.0.0",
      setup: <<~RUBY
        Mcweb::Plugins::Marketplace::Setup.define do
          upgrade_step("write_version_2", to: "1.5.0") do
            SiteSetting.set(#{key.inspect}, { "version" => 2 })
          end
          upgrade_step("fail_version_2", to: "2.0.0") { raise "token=upgrade-secret" }
        end
      RUBY
    )

    error = assert_raises(Mcweb::Plugins::Marketplace::LifecycleError) { install(upgrade) }

    refute_includes error.message, "upgrade-secret"
    assert_equal({ "version" => 1 }, SiteSetting.get(key))
    manifest = Mcweb::Plugins::Manifest.load_file(@root.join("acme/demo/mcweb_plugin.yml"))
    assert_equal "1.0.0", manifest.version
    assert_equal "active", catalog_from_disk.sole.fetch(:status)
    assert_equal receipt_before, @state_root.join("receipts/acme/demo.json").binread
    refute_includes @manager.status.fetch(:operations).to_json, "upgrade-secret"
  end

  test "completed step IDs make execution idempotent" do
    setup_path = @temporary.join("idempotent_setup.rb")
    setup_path.write(<<~RUBY)
      Mcweb::Plugins::Marketplace::Setup.define do
        install_step("only_once") { $mcweb_setup_lifecycle_hits << "hit" }
      end
    RUBY
    plan = Mcweb::Plugins::Marketplace::Setup.load_file(
      setup_path,
      plugin_id: "acme/demo",
      package_version: "1.0.0"
    )
    state = Mcweb::Plugins::Marketplace::Setup::State.empty

    ActiveRecord::Base.connection_pool.with_connection do |connection|
      state = Mcweb::Plugins::Marketplace::Setup.execute(
        plan:,
        phase: :install,
        state:,
        plugin_id: "acme/demo",
        from_version: nil,
        to_version: "1.0.0",
        operation_id: "operation-1",
        connection:,
        clock: -> { Time.utc(2026, 7, 25) }
      )
      state = Mcweb::Plugins::Marketplace::Setup.execute(
        plan:,
        phase: :install,
        state:,
        plugin_id: "acme/demo",
        from_version: nil,
        to_version: "1.0.0",
        operation_id: "operation-2",
        connection:,
        clock: -> { Time.utc(2026, 7, 25) }
      )
    end

    assert_equal [ "hit" ], $mcweb_setup_lifecycle_hits
    assert_equal [ "only_once" ], state.completed_steps.pluck("id")
  end

  test "failed install rolls database filesystem runtime and receipt back with a redacted error" do
    key = setting_key
    package = plugin_package(
      setup: <<~RUBY
        Mcweb::Plugins::Marketplace::Setup.define do
          install_step("write_setting") { SiteSetting.set(#{key.inspect}, { "partial" => true }) }
          install_step("explode") { raise "access_token=never-persist C:/private/setup.rb" }
        end
      RUBY
    )

    error = assert_raises(Mcweb::Plugins::Marketplace::LifecycleError) { install(package) }

    assert_includes error.message, "plugin setup install step explode failed (RuntimeError)"
    refute_includes error.message, "never-persist"
    assert_nil SiteSetting.get(key)
    refute @root.join("acme/demo").exist?
    assert_empty catalog_from_disk
    snapshot = @manager.status
    assert_empty snapshot.fetch(:plugins)
    refute_includes snapshot.fetch(:operations).to_json, "never-persist"
  end

  test "failed uninstall rolls database filesystem runtime and receipt back" do
    key = setting_key
    package = plugin_package(
      setup: <<~RUBY
        Mcweb::Plugins::Marketplace::Setup.define do
          install_step("write_setting") { SiteSetting.set(#{key.inspect}, { "installed" => true }) }
          uninstall_step "remove_then_fail" do
            SiteSetting.unset(#{key.inspect})
            raise "password=do-not-log"
          end
        end
      RUBY
    )
    install(package)
    receipt_before = @state_root.join("receipts/acme/demo.json").binread

    error = assert_raises(Mcweb::Plugins::Marketplace::LifecycleError) do
      uninstall
    end

    assert_includes error.message, "plugin setup uninstall step remove_then_fail failed (RuntimeError)"
    refute_includes error.message, "do-not-log"
    assert_equal({ "installed" => true }, SiteSetting.get(key))
    assert @root.join("acme/demo/mcweb_plugin.yml").file?
    assert_equal "active", catalog_from_disk.sole.fetch(:status)
    assert_equal receipt_before, @state_root.join("receipts/acme/demo.json").binread
    refute_includes @manager.status.fetch(:operations).to_json, "do-not-log"
  end

  test "duplicate step IDs and missing setup files fail before activation" do
    duplicate = plugin_package(
      setup: <<~RUBY
        Mcweb::Plugins::Marketplace::Setup.define do
          install_step("same") { nil }
          uninstall_step("same") { nil }
        end
      RUBY
    )
    error = assert_raises(Mcweb::Plugins::Marketplace::SetupError) { install(duplicate) }
    assert_includes error.message, "duplicate"
    refute @root.join("acme/demo").exist?

    missing = plugin_package(setup: nil, setup_path: "db/missing.rb")
    assert_raises(Mcweb::Plugins::Marketplace::SetupError) { install(missing) }
    refute @root.join("acme/demo").exist?
  end

  test "packages without setup preserve the existing marketplace behavior" do
    result = install(plugin_package)

    assert_equal "active", result.status
    plugin = @manager.status.fetch(:plugins).sole
    refute plugin.key?(:setup)
    @manager.disable(plugin_id: "acme/demo")
    @manager.enable(plugin_id: "acme/demo")
    assert_equal "active", @manager.status.fetch(:plugins).sole.fetch(:status)
  end

  private

  def build_manager
    catalog = -> { catalog_from_disk }
    Mcweb::Plugins::Marketplace::Manager.new(
      root: @root,
      state_root: @state_root,
      reload_callback: catalog,
      runtime_catalog: catalog,
      ruby_version: "4.0.6",
      rails_version: "8.1.2"
    )
  end

  def catalog_from_disk
    @root.glob("**/mcweb_plugin.yml").map do |path|
      manifest = Mcweb::Plugins::Manifest.load_file(path)
      { id: manifest.id, status: "active" }
    end
  end

  def install(package)
    @manager.install(
      package_path: package,
      source: "file:///reviewed/#{package.basename}",
      expected_sha256: Digest::SHA256.file(package).hexdigest
    )
  end

  def uninstall(expected_version: nil, expected_sha256: nil)
    plugin = @manager.status(plugin_id: "acme/demo").fetch(:plugins).sole
    @manager.uninstall(
      plugin_id: "acme/demo",
      expected_version: expected_version || plugin.fetch(:version),
      expected_sha256: expected_sha256 || plugin.fetch(:sha256)
    )
  end

  def plugin_package(version: "1.0.0", setup: nil, setup_path: nil)
    path = @temporary.join("acme-demo-#{version}-#{SecureRandom.hex(4)}.zip")
    setup_path ||= "db/setup.rb" if setup
    manifest = {
      "id" => "acme/demo",
      "name" => "Demo",
      "version" => version,
      "api_version" => "1",
      "entrypoint" => "plugin.rb",
      "setup" => setup_path
    }.compact
    Zip::File.open(path, create: true) do |archive|
      archive.get_output_stream("mcweb_plugin.yml") { |stream| stream.write(manifest.to_yaml) }
      archive.get_output_stream("plugin.rb") { |stream| stream.write("PLUGIN = true\n") }
      archive.get_output_stream(setup_path) { |stream| stream.write(setup) } if setup
    end
    path
  end

  def setting_key
    "test.plugin_setup.#{SecureRandom.hex(12)}".tap { |key| @setting_keys << key }
  end
end
