# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/settings_store"
require "mcweb/plugin_api/v1/host"
require "tmpdir"

class Mcweb::PluginApi::V1::SettingsTest < ActiveSupport::TestCase
  class NullEventBus
    def publish(*)
      true
    end
  end

  setup do
    @root = Pathname(Dir.mktmpdir("mcweb-plugin-settings-api"))
    @actor = create_user
  end

  teardown do
    FileUtils.remove_entry(@root) if @root&.exist?
  end

  test "setting versions are encrypted append-only and audit metadata never contains values" do
    schema = setting_schema(version: "1")
    store = Mcweb::Plugins::SettingsStore.new(
      plugin_id: "acme/settings",
      schema:
    )

    first = store.update(
      values: {
        "endpoint" => "https://one.example.test",
        "api_token" => "top-secret-token"
      },
      expected_revision: 0,
      actor: @actor,
      audit: { ip_address: "127.0.0.1", user_agent: "Settings test" }
    )
    second = store.update(
      values: { "endpoint" => "https://two.example.test" },
      expected_revision: 1,
      actor: @actor
    )

    assert_equal 1, first.revision
    assert_equal 2, second.revision
    assert_equal "top-secret-token", second.values.fetch("api_token")
    records = PluginSettingVersion.for_namespace("acme/settings", "1").order(:revision)
    assert_equal 2, records.count
    records.each do |record|
      refute_includes record.encrypted_values, "top-secret-token"
      refute_includes record.encrypted_values, "https://"
    end

    audit_text = AuditLog
      .where(action: %w[plugin.settings.update plugin.settings.migration plugin.settings.rollback])
      .order(:id)
      .map { |audit| [ audit.metadata, audit.before_state, audit.after_state ].to_json }
      .join
    refute_includes audit_text, "top-secret-token"
    refute_includes audit_text, "https://one.example.test"
    refute_includes audit_text, "https://two.example.test"
    assert_includes audit_text, "changed_keys"

    record = records.first
    assert_not record.update(schema_version: "2")
    assert_not record.destroy
    assert_predicate record.reload, :persisted?
  end

  test "schema versions are isolated and forward migration leaves the old version available" do
    v1 = setting_schema(version: "1")
    v1_store = Mcweb::Plugins::SettingsStore.new(
      plugin_id: "acme/settings",
      schema: v1
    )
    v1_store.update(
      values: {
        "endpoint" => "https://legacy.example.test",
        "api_token" => "legacy-secret"
      },
      expected_revision: 0,
      actor: @actor
    )

    v2 = setting_schema(version: "2", renamed_endpoint: true)
    v2_store = Mcweb::Plugins::SettingsStore.new(
      plugin_id: "acme/settings",
      schema: v2
    )
    pending = v2_store.snapshot
    assert_equal 0, pending.revision
    assert pending.migration_available

    migrated = v2_store.migrate(expected_revision: 0, actor: @actor)
    assert_equal 1, migrated.revision
    assert_equal "https://legacy.example.test", migrated.values.fetch("base_url")
    assert_equal "legacy-secret", migrated.values.fetch("api_token")

    old_snapshot = v1_store.snapshot
    assert_equal 1, old_snapshot.revision
    assert_equal "https://legacy.example.test", old_snapshot.values.fetch("endpoint")
    assert_equal 1, PluginSettingVersion.for_namespace("acme/settings", "1").count
    assert_equal 1, PluginSettingVersion.for_namespace("acme/settings", "2").count

    v1_store.update(
      values: { "endpoint" => "https://changed-after-downgrade.example.test" },
      expected_revision: 1,
      actor: @actor
    )
    assert v2_store.snapshot.migration_available
    error = assert_raises(Mcweb::Plugins::SettingValidationError) do
      v2_store.update(
        values: { "base_url" => "https://stale.example.test" },
        expected_revision: 1,
        actor: @actor
      )
    end
    assert_equal "migration_required", error.code

    remigrated = v2_store.migrate(expected_revision: 1, actor: @actor)
    assert_equal 2, remigrated.revision
    assert_equal(
      "https://changed-after-downgrade.example.test",
      remigrated.values.fetch("base_url")
    )
  end

  test "reupgrade migrates the newest compatible namespace instead of the highest old version" do
    v1_document = setting_document(version: "1")
    v2_document = setting_document(version: "2", renamed_endpoint: true)
    v3_document = v2_document.deep_dup
    v3_document["schema_version"] = "3"
    v3_document["schema"]["required"][0] = "service_url"
    v3_document["schema"]["properties"]["service_url"] =
      v3_document["schema"]["properties"].delete("base_url")
    v3_document["migrations"] << {
      "from" => "2",
      "to" => "3",
      "rename" => { "base_url" => "service_url" },
      "remove" => [],
      "defaults" => {}
    }

    stores = [ v1_document, v2_document, v3_document ].map do |document|
      Mcweb::Plugins::SettingsStore.new(
        plugin_id: "acme/settings",
        schema: Mcweb::Plugins::SettingSchema.new(
          plugin_id: "acme/settings",
          document:
        )
      )
    end
    v1_store, v2_store, v3_store = stores
    v1_store.update(
      values: {
        "endpoint" => "https://initial.example.test",
        "api_token" => "secret"
      },
      expected_revision: 0,
      actor: @actor
    )
    v2_store.migrate(expected_revision: 0, actor: @actor)
    v3_store.migrate(expected_revision: 0, actor: @actor)

    v1_store.update(
      values: { "endpoint" => "https://newest.example.test" },
      expected_revision: 1,
      actor: @actor
    )

    assert v3_store.snapshot.migration_available
    remigrated = v3_store.migrate(expected_revision: 1, actor: @actor)
    assert_equal "https://newest.example.test", remigrated.values.fetch("service_url")
    record = PluginSettingVersion
      .for_namespace("acme/settings", "3")
      .find_by!(revision: remigrated.revision)
    assert_equal "1", record.migration_source.schema_version
  end

  test "rollback appends a new validated revision and optimistic concurrency rejects stale writes" do
    schema = setting_schema(version: "1")
    store = Mcweb::Plugins::SettingsStore.new(
      plugin_id: "acme/settings",
      schema:
    )
    store.update(
      values: {
        "endpoint" => "https://first.example.test",
        "api_token" => "secret"
      },
      expected_revision: 0,
      actor: @actor
    )
    store.update(
      values: { "endpoint" => "https://second.example.test" },
      expected_revision: 1,
      actor: @actor
    )

    conflict = assert_raises(Mcweb::Plugins::SettingValidationError) do
      store.update(
        values: { "endpoint" => "https://stale.example.test" },
        expected_revision: 1,
        actor: @actor
      )
    end
    assert_equal "revision_conflict", conflict.code

    rolled_back = store.rollback(
      revision: 1,
      expected_revision: 2,
      actor: @actor
    )
    assert_equal 3, rolled_back.revision
    assert_equal "https://first.example.test", rolled_back.values.fetch("endpoint")
    record = PluginSettingVersion.for_namespace("acme/settings", "1").find_by!(revision: 3)
    assert_equal "rollback", record.change_kind
    assert_equal 1, record.rollback_source.revision
  end

  test "host settings facade is namespace-bound immutable and capability-audited" do
    audits = []
    manifest = write_plugin(setting_document(version: "1"))
    host = Mcweb::PluginApi::V1::Host.new(
      manifest:,
      event_bus: NullEventBus.new,
      capability_auditor: ->(capability) { audits << capability }
    )

    descriptor = host.settings.descriptor
    assert_predicate descriptor, :success?
    assert_equal "acme/settings", descriptor.value.fetch("plugin_id")
    refute descriptor.value.fetch("properties")
      .find { |property| property.fetch("key") == "api_token" }
      .key?("configured")

    updated = host.settings.update(
      values: {
        endpoint: "https://api.example.test",
        api_token: "runtime-secret"
      },
      expected_revision: 0
    )
    assert_predicate updated, :success?
    assert_equal "runtime-secret", updated.value.fetch("values").fetch("api_token")
    assert_predicate updated.value, :frozen?
    assert_raises(FrozenError) { updated.value.fetch("values")["api_token"] = "changed" }

    secret = host.settings.get("api_token")
    assert_equal "runtime-secret", secret.value
    undeclared = host.settings.get("other.plugin.secret")
    assert_predicate undeclared, :failure?
    assert_equal "setting_not_declared", undeclared.code

    assert_equal [ "acme/settings" ], PluginSettingVersion.distinct.pluck(:plugin_id)
    assert_equal 3, audits.count("plugin.settings.read")
    assert_equal 1, audits.count("plugin.settings.write")
  end

  test "runtime writes require an expected revision and cannot silently overwrite" do
    manifest = write_plugin(setting_document(version: "1"))
    host = Mcweb::PluginApi::V1::Host.new(
      manifest:,
      event_bus: NullEventBus.new
    )

    update = host.settings.update(
      values: {
        endpoint: "https://api.example.test",
        api_token: "secret"
      }
    )
    migrate = host.settings.migrate
    rollback = host.settings.rollback(revision: 1)

    [ update, migrate, rollback ].each do |result|
      assert_predicate result, :failure?
      assert_equal "invalid_argument", result.code
    end
    assert_empty PluginSettingVersion.where(plugin_id: "acme/settings")
  end

  test "a plugin without a schema gets an explicit result and cannot write host settings" do
    manifest = Mcweb::Plugins::Manifest.from_hash({
      id: "acme/no-settings",
      name: "No settings",
      version: "1.0.0",
      api_version: "1"
    })
    host = Mcweb::PluginApi::V1::Host.new(
      manifest:,
      event_bus: NullEventBus.new
    )

    assert_equal "settings_not_declared", host.settings.values.code
    assert_equal(
      "settings_not_declared",
      host.settings.update(values: { "host.secret" => "no" }).code
    )
    assert_empty PluginSettingVersion.where(plugin_id: "acme/no-settings")
  end

  private

  def setting_schema(version:, renamed_endpoint: false)
    Mcweb::Plugins::SettingSchema.new(
      plugin_id: "acme/settings",
      document: setting_document(version:, renamed_endpoint:)
    )
  end

  def setting_document(version:, renamed_endpoint: false)
    endpoint_key = renamed_endpoint ? "base_url" : "endpoint"
    migrations = if renamed_endpoint
      [
        {
          "from" => "1",
          "to" => "2",
          "rename" => { "endpoint" => "base_url" },
          "remove" => [],
          "defaults" => {}
        }
      ]
    else
      []
    end

    {
      "schema_version" => version,
      "groups" => {
        "general" => {
          "title_phrase" => "acme.settings.settings.general.title",
          "position" => 10
        }
      },
      "schema" => {
        "$schema" => Mcweb::Plugins::SettingSchema::DRAFT_URI,
        "type" => "object",
        "additionalProperties" => false,
        "required" => [ endpoint_key, "api_token" ],
        "properties" => {
          endpoint_key => {
            "type" => "string",
            "format" => "url",
            "x-mcweb-title-phrase" => "acme.settings.settings.endpoint.title",
            "x-mcweb-group" => "general",
            "x-mcweb-input" => "url"
          },
          "api_token" => {
            "type" => "string",
            "minLength" => 1,
            "x-mcweb-title-phrase" => "acme.settings.settings.api_token.title",
            "x-mcweb-group" => "general",
            "x-mcweb-sensitive" => true,
            "x-mcweb-input" => "password"
          }
        }
      },
      "migrations" => migrations
    }
  end

  def write_plugin(document)
    directory = @root.join("plugin")
    FileUtils.mkdir_p(directory.join("config"))
    File.write(directory.join("config/settings.yml"), YAML.dump(document))
    File.write(
      directory.join("mcweb_plugin.yml"),
      YAML.dump(
        "id" => "acme/settings",
        "name" => "Settings",
        "version" => "1.0.0",
        "api_version" => "1",
        "capabilities" => %w[plugin.settings.read plugin.settings.write],
        "contributions" => { "settings" => "config/settings.yml" }
      )
    )
    Mcweb::Plugins::Manifest.load_file(directory.join("mcweb_plugin.yml"))
  end
end
