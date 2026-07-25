# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class Mcweb::ApplicationRegistryTest < ActiveSupport::TestCase
  test "defines platform modules applications and extensions" do
    assert Mcweb::ApplicationRegistry.platform_modules.any? { |m| m.id == :identity }
    assert Mcweb::ApplicationRegistry.applications.any? { |a| a.id == :forum }
    assert Mcweb::ApplicationRegistry.applications.any? { |a| a.id == :store }
    assert Mcweb::ApplicationRegistry.extensions.any? { |e| e.id == :mcweb_connector }
    assert Mcweb::ApplicationRegistry.extensions.any? { |e| e.id == :trusted_ruby_plugins }
  end

  test "application_for_path resolves forum and store" do
    assert_equal :forum, Mcweb::ApplicationRegistry.application_for_path("/app/forum/sections").id
    assert_equal :store, Mcweb::ApplicationRegistry.application_for_path("/app/store/products").id
  end

  test "trusted deployment plugins are an extension tier" do
    assert Mcweb::ApplicationRegistry.freely_extensible?,
      "extensible means fully trusted deployment code, not untrusted uploads"
    assert_equal :deployment, Mcweb::ApplicationRegistry.plugin_installation_mode

    extension = Mcweb::ApplicationRegistry.find_extension(:trusted_ruby_plugins)
    assert_equal :trusted_ruby_plugin_sdk, extension.kind
    assert extension.limitations.any? { |line| line.include?("不是权限控制或安全沙箱") }
  end

  test "admin catalog includes enabled flag for applications" do
    catalog = Mcweb::ApplicationRegistry.admin_catalog
    forum = catalog[:applications].find { |a| a[:id] == "forum" }

    assert forum
    assert_equal FeatureFlags.enabled?(:forum), forum[:enabled]
  end
end

class AdminSystemApplicationsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    grant_admin_module(@admin, "system")

    Mcweb::Plugins.reset!
    Mcweb::Plugins.register(
      id: "acme/base",
      name: "Base plugin",
      version: "1.0.0",
      api_version: "1",
      capabilities: []
    )
    Mcweb::Plugins.register(
      id: "acme/catalog",
      name: "Catalog plugin",
      version: "1.2.3",
      api_version: "1",
      description: "Visible in the admin catalog",
      requires: { "acme/base" => ">= 1.0.0" },
      capabilities: [ "forum.events.read" ]
    ) do |plugin|
      plugin.on("forum.catalog.test") { |_event| nil }
    end
    Mcweb::Plugins.boot!
    Mcweb::Plugins.registry.record_diagnostic(
      level: :warning,
      code: :catalog_test,
      phase: :activation,
      plugin_id: "acme/catalog",
      message: "Catalog diagnostic"
    )
  end

  teardown do
    Mcweb::Plugins.reset!
  end

  test "applications index for system admin" do
    sign_in_as(@admin)
    get admin_system_applications_path

    assert_response :success
    assert_includes response.body, "applications"
    assert_includes response.body, "forum"
    assert_includes response.body, "mcweb_connector"

    props = inertia.props.deep_symbolize_keys
    plugin = props[:plugins].find { |entry| entry[:id] == "acme/catalog" }
    assert_equal "1.2.3", plugin[:version]
    assert_equal "active", plugin[:status]
    assert_equal 1, plugin[:listener_count]
    assert_equal [ "forum.events.read" ], plugin[:capabilities]
    assert_equal({ "acme/base": ">= 1.0.0" }, plugin[:requires])
    assert(props[:pluginDiagnostics].any? do |entry|
      entry[:code] == "catalog_test" && entry[:plugin_id] == "acme/catalog"
    end)
  end
end
