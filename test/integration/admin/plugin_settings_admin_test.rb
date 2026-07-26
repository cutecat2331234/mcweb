# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"
require "mcweb/plugins/registry"
require "tmpdir"

module Admin
  class PluginSettingsAdminTest < ActionDispatch::IntegrationTest
    setup do
      @root = Pathname(Dir.mktmpdir("mcweb-admin-plugin-settings"))
      @admin = create_user
      grant_permission(@admin, "admin.access")
      grant_permission(@admin, "system.plugins.settings.manage")
      grant_admin_module(@admin, "system")
      sign_in_as(@admin)

      Mcweb::Plugins.reset!
      register_schema(version: "1")
    end

    teardown do
      Mcweb::Plugins.reset!
      FileUtils.remove_entry(@root) if @root&.exist?
    end

    test "page renders schema fields but never returns an existing sensitive value" do
      get admin_system_plugin_settings_path, params: { plugin_id: "acme/settings" }

      assert_response :success
      assert_equal "no-store", response.headers["Cache-Control"]
      props = inertia.props.deep_symbolize_keys
      selected = props.fetch(:selected)
      assert_equal "acme/settings", selected.fetch(:plugin_id)
      token = selected.fetch(:groups).flat_map { |group| group.fetch(:fields) }
        .find { |field| field.fetch(:key) == "api_token" }
      assert_nil token.fetch(:value)
      refute token.fetch(:configured)

      patch admin_system_plugin_settings_path, params: {
        plugin_id: "acme/settings",
        expected_revision: 0,
        values: {
          endpoint: "https://api.example.test",
          api_token: "admin-secret"
        }
      }
      assert_redirected_to admin_system_plugin_settings_path(plugin_id: "acme/settings")

      get admin_system_plugin_settings_path, params: { plugin_id: "acme/settings" }
      selected = inertia.props.deep_symbolize_keys.fetch(:selected)
      token = selected.fetch(:groups).flat_map { |group| group.fetch(:fields) }
        .find { |field| field.fetch(:key) == "api_token" }
      assert_nil token.fetch(:value)
      assert token.fetch(:configured)
      refute_includes response.body, "admin-secret"
      refute_includes PluginSettingVersion.last.encrypted_values, "admin-secret"

      audit = AuditLog.find_by!(action: "plugin.settings.update")
      serialized_audit = [ audit.metadata, audit.before_state, audit.after_state ].to_json
      refute_includes serialized_audit, "admin-secret"
      refute_includes serialized_audit, "https://api.example.test"
    end

    test "a dedicated permission protects reads and mutations" do
      permission = Permission.find_by!(key: "system.plugins.settings.manage")
      @admin.roles
        .joins(:permissions)
        .where(permissions: { id: permission.id })
        .each { |role| @admin.roles.delete(role) }
      grant_permission(@admin, "system.plugins.manage")

      get admin_system_plugin_settings_path
      assert_redirected_to root_path

      patch admin_system_plugin_settings_path, params: {
        plugin_id: "acme/settings",
        expected_revision: 0,
        values: {
          endpoint: "https://forbidden.example.test",
          api_token: "forbidden"
        }
      }
      assert_redirected_to root_path
      assert_empty PluginSettingVersion.where(plugin_id: "acme/settings")
    end

    test "strict schema errors are rendered without persisting submitted secrets" do
      patch admin_system_plugin_settings_path, params: {
        plugin_id: "acme/settings",
        expected_revision: 0,
        values: {
          endpoint: "not-a-url",
          api_token: "must-not-echo",
          unexpected: "value"
        }
      }

      assert_response :unprocessable_entity
      props = inertia.props.deep_symbolize_keys
      assert props.dig(:selected, :page_error).present?
      endpoint = props.dig(:selected, :groups).flat_map { |group| group.fetch(:fields) }
        .find { |field| field.fetch(:key) == "endpoint" }
      assert endpoint.fetch(:error).present?
      refute_includes response.body, "must-not-echo"
      assert_empty PluginSettingVersion.where(plugin_id: "acme/settings")
      assert_empty AuditLog.where(action: "plugin.settings.update")
    end

    test "malformed collection payloads are rejected instead of being coerced" do
      patch admin_system_plugin_settings_path, params: {
        plugin_id: "acme/settings",
        expected_revision: 0,
        values: [ "not", "a", "mapping" ]
      }
      assert_response :unprocessable_entity

      patch admin_system_plugin_settings_path, params: {
        plugin_id: "acme/settings",
        expected_revision: 0,
        values: {
          endpoint: "https://api.example.test",
          api_token: "must-not-persist"
        },
        unset_keys: "endpoint"
      }
      assert_response :unprocessable_entity
      assert_empty PluginSettingVersion.where(plugin_id: "acme/settings")
    end

    test "rollback appends a new revision and keeps the encrypted history immutable" do
      update_settings(
        revision: 0,
        endpoint: "https://first.example.test",
        token: "stable-secret"
      )
      update_settings(
        revision: 1,
        endpoint: "https://second.example.test",
        token: ""
      )

      post rollback_admin_system_plugin_settings_path, params: {
        plugin_id: "acme/settings",
        expected_revision: 2,
        revision: 1
      }

      assert_redirected_to admin_system_plugin_settings_path(plugin_id: "acme/settings")
      versions = PluginSettingVersion.for_namespace("acme/settings", "1").order(:revision)
      assert_equal [ 1, 2, 3 ], versions.pluck(:revision)
      assert_equal "rollback", versions.last.change_kind
      assert_equal "https://first.example.test", versions.last.values_hash.fetch("endpoint")
      assert_equal "stable-secret", versions.last.values_hash.fetch("api_token")
    end

    test "explicit migration creates a new schema namespace and preserves the old one" do
      update_settings(
        revision: 0,
        endpoint: "https://legacy.example.test",
        token: "legacy-secret"
      )

      Mcweb::Plugins.reset!
      register_schema(version: "2")

      get admin_system_plugin_settings_path, params: { plugin_id: "acme/settings" }
      selected = inertia.props.deep_symbolize_keys.fetch(:selected)
      assert selected.fetch(:migration_available)
      assert_equal 0, selected.fetch(:revision)

      post migrate_admin_system_plugin_settings_path, params: {
        plugin_id: "acme/settings",
        expected_revision: 0
      }

      assert_redirected_to admin_system_plugin_settings_path(plugin_id: "acme/settings")
      old_version = PluginSettingVersion.for_namespace("acme/settings", "1").sole
      new_version = PluginSettingVersion.for_namespace("acme/settings", "2").sole
      assert_equal "https://legacy.example.test", old_version.values_hash.fetch("endpoint")
      assert_equal "https://legacy.example.test", new_version.values_hash.fetch("base_url")
      assert_equal "migration", new_version.change_kind
      assert_equal old_version, new_version.migration_source
    end

    private

    def update_settings(revision:, endpoint:, token:)
      patch admin_system_plugin_settings_path, params: {
        plugin_id: "acme/settings",
        expected_revision: revision,
        values: {
          endpoint:,
          api_token: token
        }
      }
      assert_response :redirect
    end

    def register_schema(version:)
      directory = @root.join("plugin-v#{version}")
      FileUtils.mkdir_p(directory.join("config"))
      File.write(
        directory.join("config/settings.yml"),
        YAML.dump(settings_document(version:))
      )
      File.write(
        directory.join("mcweb_plugin.yml"),
        YAML.dump(
          "id" => "acme/settings",
          "name" => "Settings",
          "version" => "#{version}.0.0",
          "api_version" => "1",
          "contributions" => { "settings" => "config/settings.yml" }
        )
      )
      manifest = Mcweb::Plugins::Manifest.load_file(directory.join("mcweb_plugin.yml"))
      Mcweb::Plugins.register(manifest)
      Mcweb::Plugins.boot!
    end

    def settings_document(version:)
      endpoint_key = version == "1" ? "endpoint" : "base_url"
      migrations = if version == "2"
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
  end
end
