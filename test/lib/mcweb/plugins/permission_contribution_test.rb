# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/registry"
require "tmpdir"

class Mcweb::Plugins::PermissionContributionTest < ActiveSupport::TestCase
  setup do
    @root = Pathname(Dir.mktmpdir("mcweb-permission-contributions"))
    @registry = Mcweb::Plugins::Registry.new(logger: Logger.new(IO::NULL))
    @previous_disable_plugins = ENV["MCWEB_DISABLE_PLUGINS"]
    ENV.delete("MCWEB_DISABLE_PLUGINS")
  end

  teardown do
    @registry.reset!
    FileUtils.remove_entry(@root) if @root&.exist?
    if @previous_disable_plugins.nil?
      ENV.delete("MCWEB_DISABLE_PLUGINS")
    else
      ENV["MCWEB_DISABLE_PLUGINS"] = @previous_disable_plugins
    end
  end

  test "manifest normalizes and deeply owns the permission contribution path" do
    path = +"./config/permissions.yml"
    attributes = base_manifest_hash(
      id: "acme/demo",
      contributions: { permissions: path }
    )

    manifest = Mcweb::Plugins::Manifest.from_hash(attributes)
    path << ".changed"

    assert_equal(
      { "permissions" => "config/permissions.yml" },
      manifest.contributions
    )
    assert_equal "config/permissions.yml", manifest.permission_contributions_path
    assert_predicate manifest.contributions, :frozen?
    assert_predicate manifest.contributions.keys.first, :frozen?
    assert_predicate manifest.permission_contributions_path, :frozen?

    invalid_contributions = [
      [],
      { permissions: "../permissions.yml" },
      { permissions: "config/permissions.json" },
      { permissions: "config\\permissions.yml" },
      { permissions: "config/permissions.yml", "permissions" => "other.yml" },
      { navigation: "config/navigation.yml" }
    ]
    invalid_contributions.each do |contributions|
      assert_raises(Mcweb::Plugins::ManifestError) do
        Mcweb::Plugins::Manifest.from_hash(
          base_manifest_hash(id: "acme/invalid", contributions:)
        )
      end
    end
  end

  test "permission contribution file is strict bounded and deeply immutable" do
    manifest = write_plugin(
      directory: "valid",
      id: "acme/identity",
      permissions: [
        permission_attributes(
          id: "acme.identity.orders.view",
          group: "acme.identity.orders",
          default: "staff"
        )
      ]
    )

    contribution = Mcweb::Plugins::PermissionContributionLoader.load(manifest).sole

    assert_equal "acme/identity", contribution.plugin_id
    assert_equal "acme.identity.orders.view", contribution.id
    assert_equal "acme.identity.orders", contribution.group
    assert_equal "permission.order_view.title", contribution.title_phrase
    assert_equal "permission.order_view.description", contribution.description_phrase
    assert_equal "global", contribution.scope
    assert_equal "staff", contribution.default
    assert_predicate contribution, :frozen?
    assert_predicate contribution.to_h, :frozen?
    contribution.to_h.each_value { |value| assert_predicate value, :frozen? }

    invalid_entries = [
      permission_attributes(id: "other.plugin.orders.view"),
      permission_attributes(id: "mcweb.system.manage"),
      permission_attributes(group: "other.plugin.orders"),
      permission_attributes(title_phrase: "Invalid phrase"),
      permission_attributes(description_phrase: "invalid"),
      permission_attributes(scope: "channel"),
      permission_attributes(default: "allow"),
      permission_attributes.merge("unknown" => "value"),
      permission_attributes.except("description_phrase")
    ]
    invalid_entries.each do |entry|
      write_permissions(manifest, [ entry ])
      assert_raises(Mcweb::Plugins::ManifestError) do
        Mcweb::Plugins::PermissionContributionLoader.load(manifest)
      end
    end

    write_permissions(manifest, [ permission_attributes, permission_attributes ])
    duplicate_error = assert_raises(Mcweb::Plugins::ManifestError) do
      Mcweb::Plugins::PermissionContributionLoader.load(manifest)
    end
    assert_includes duplicate_error.message, "duplicate permission contribution ids"

    permissions_path = permission_path_for(manifest)
    File.write(
      permissions_path,
      <<~YAML
        permissions:
          - id: acme.identity.orders.view
            id: acme.identity.orders.edit
            group: acme.identity.orders
            title_phrase: permission.order_view.title
            description_phrase: permission.order_view.description
            scope: global
            default: none
      YAML
    )
    yaml_error = assert_raises(Mcweb::Plugins::ManifestError) do
      Mcweb::Plugins::PermissionContributionLoader.load(manifest)
    end
    assert_includes yaml_error.message, "duplicate permission contribution key"
  end

  test "hyphenated manifest ids map to host-compatible permission namespaces" do
    manifest = write_plugin(
      directory: "hyphenated",
      id: "acme/demo-tools",
      permissions: [
        permission_attributes(
          id: "acme.demo_tools.orders.view",
          group: "acme.demo_tools.orders"
        )
      ]
    )

    contribution = Mcweb::Plugins::PermissionContributionLoader.load(manifest).sole

    assert_equal "acme.demo_tools.orders.view", contribution.id
    assert_equal "acme.demo_tools.orders", contribution.group
  end

  test "core permission namespaces cannot be claimed by plugins" do
    manifest = write_plugin(
      directory: "reserved-core-namespace",
      id: "system/jobs",
      permissions: [
        permission_attributes(
          id: "system.jobs.retry",
          group: "system.jobs"
        )
      ]
    )

    error = assert_raises(Mcweb::Plugins::ManifestError) do
      Mcweb::Plugins::PermissionContributionLoader.load(manifest)
    end

    assert_includes error.message, "reserved by McWeb core"
  end

  test "active contributions are queryable and authorization remains host controlled" do
    permission_key = "acme.identity.orders.view"
    manifest = write_plugin(
      directory: "authorization",
      id: "acme/identity",
      permissions: [
        permission_attributes(
          id: permission_key,
          group: "acme.identity.orders",
          default: "staff"
        )
      ]
    )
    counts_before = [ Permission.count, UserRole.count, RolePermission.count ]
    definition = @registry.register(manifest)
    @registry.boot!

    assert_equal counts_before, [ Permission.count, UserRole.count, RolePermission.count ],
                 "default recommendations must never grant roles or permissions"
    assert_equal "active", definition.status.to_s
    assert_equal 1, definition.to_h.fetch(:permission_contribution_count)

    catalog = definition.api.identity.permission_contributions
    assert_predicate catalog, :success?
    assert_equal [ permission_key ], catalog.value.pluck("id")
    assert_equal "identity.permission_contribution", catalog.value.first.fetch("type")
    assert_predicate catalog.value, :frozen?
    assert_predicate catalog.value.first, :frozen?
    refute contains_active_record?(catalog.value)

    descriptor = definition.api.identity.permission_contribution(key: permission_key)
    assert_predicate descriptor, :success?
    assert_equal "global", descriptor.value.fetch("scope")
    assert_equal "staff", descriptor.value.fetch("default")

    user = create_user
    group = Community::UserGroup.create!(
      name: "Plugin operators",
      priority: 40,
      permissions: []
    )
    Community::GroupMembership.create!(user:, user_group: group, is_primary: true)

    denied = definition.api.identity.plugin_permission(id: user.id, key: permission_key)
    refute denied.value.fetch("allowed")
    assert_equal "not_granted", denied.value.fetch("reason")

    group.update!(permissions: [ permission_key ])
    allowed = definition.api.identity.plugin_permission(id: user.id, key: permission_key)
    assert allowed.value.fetch("allowed")
    assert_equal "granted_by_group", allowed.value.fetch("reason")
    assert_equal "global", allowed.value.fetch("scope")
    assert_equal permission_key, allowed.value.dig("contribution", "id")
    assert_equal [ "group" ], allowed.value.fetch("sources").pluck("type")

    user.ban!(reason: "security test")
    banned = definition.api.identity.plugin_permission(id: user.id, key: permission_key)
    refute banned.value.fetch("allowed")
    assert_equal "account_banned", banned.value.fetch("reason")
    user.unban!

    group.update!(permissions: [])
    revoked = definition.api.identity.plugin_permission(id: user.id, key: permission_key)
    refute revoked.value.fetch("allowed"),
           "the same User instance must observe global group permission changes"

    undeclared_key = "acme.identity.orders.export"
    group.update!(permissions: [ undeclared_key ])
    assert user.permission?(undeclared_key)
    unavailable = definition.api.identity.plugin_permission(
      id: user.id,
      key: undeclared_key
    )
    assert_predicate unavailable, :failure?
    assert_equal "not_found", unavailable.code
  end

  test "namespace collisions disable the deterministic loser without replacing the owner" do
    permission_key = "acme.foo.bar.orders.view"
    first_manifest = write_plugin(
      directory: "namespace-one",
      id: "acme.foo/bar",
      permissions: [
        permission_attributes(
          id: permission_key,
          group: "acme.foo.bar.orders"
        )
      ]
    )
    second_manifest = write_plugin(
      directory: "namespace-two",
      id: "acme/foo.bar",
      permissions: [
        permission_attributes(
          id: permission_key,
          group: "acme.foo.bar.orders"
        )
      ]
    )
    definitions = [
      @registry.register(first_manifest),
      @registry.register(second_manifest)
    ]

    @registry.boot!

    winner, loser = definitions.sort_by(&:id)
    assert_equal "active", winner.status.to_s
    assert_equal "disabled", loser.status.to_s
    assert_equal winner.id, @registry.permission_contribution(permission_key).fetch(:plugin_id)
    assert_equal [ permission_key ], @registry.permission_contributions.pluck(:id)
    assert @registry.diagnostics.any? do |entry|
      entry[:code] == "permission_contribution_conflict" &&
        entry[:plugin_id] == loser.id
    end
    assert_empty loser.api.identity.permission_contributions.value
    assert_predicate(
      loser.api.identity.permission_contribution(key: permission_key),
      :failure?
    )
  end

  test "unregister reset and global disable remove active permission contributions" do
    permission_key = "acme.cleanup.orders.view"
    manifest = write_plugin(
      directory: "cleanup",
      id: "acme/cleanup",
      permissions: [
        permission_attributes(
          id: permission_key,
          group: "acme.cleanup.orders"
        )
      ]
    )
    definition = @registry.register(manifest)
    @registry.boot!
    assert_equal [ permission_key ], @registry.permission_contributions.pluck(:id)

    @registry.unregister(manifest.id)
    assert_empty @registry.permission_contributions
    assert_empty definition.api.identity.permission_contributions.value
    assert_equal(
      "not_found",
      definition.api.identity.plugin_permission(
        id: create_user.id,
        key: permission_key
      ).code
    )

    disabled_definition = @registry.register(manifest)
    ENV["MCWEB_DISABLE_PLUGINS"] = "1"
    @registry.boot!
    assert_equal "disabled", disabled_definition.status.to_s
    assert_empty @registry.permission_contributions

    @registry.reset!
    assert_empty @registry.permission_contributions
  end

  private

  def base_manifest_hash(id:, contributions: {})
    {
      id:,
      name: id,
      version: "1.0.0",
      api_version: "1",
      capabilities: [ "identity.permissions.read" ],
      contributions:
    }
  end

  def permission_attributes(overrides = {})
    {
      "id" => "acme.identity.orders.view",
      "group" => "acme.identity.orders",
      "title_phrase" => "permission.order_view.title",
      "description_phrase" => "permission.order_view.description",
      "scope" => "global",
      "default" => "none"
    }.merge(overrides.transform_keys(&:to_s))
  end

  def write_plugin(directory:, id:, permissions:)
    plugin_dir = @root.join(directory)
    FileUtils.mkdir_p(plugin_dir.join("config"))
    manifest_path = plugin_dir.join("mcweb_plugin.yml")
    File.write(
      manifest_path,
      base_manifest_hash(
        id:,
        contributions: { permissions: "config/permissions.yml" }
      ).deep_stringify_keys.to_yaml
    )
    File.write(
      plugin_dir.join("config/permissions.yml"),
      { "permissions" => permissions }.to_yaml
    )
    Mcweb::Plugins::Manifest.load_file(manifest_path)
  end

  def write_permissions(manifest, permissions)
    File.write(
      permission_path_for(manifest),
      { "permissions" => permissions }.to_yaml
    )
  end

  def permission_path_for(manifest)
    Pathname(manifest.source_path).dirname.join(manifest.permission_contributions_path)
  end

  def contains_active_record?(value)
    case value
    when ActiveRecord::Base
      true
    when Hash
      value.any? do |key, item|
        contains_active_record?(key) || contains_active_record?(item)
      end
    when Array
      value.any? { |item| contains_active_record?(item) }
    else
      false
    end
  end
end
