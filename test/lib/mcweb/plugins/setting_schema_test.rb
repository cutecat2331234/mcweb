# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/setting_schema"
require "tmpdir"

class Mcweb::Plugins::SettingSchemaTest < ActiveSupport::TestCase
  setup do
    @root = Pathname(Dir.mktmpdir("mcweb-setting-schema"))
  end

  teardown do
    FileUtils.remove_entry(@root) if @root&.exist?
  end

  test "manifest and loader accept a strict immutable schema contribution" do
    manifest = write_plugin(valid_document)
    schema = Mcweb::Plugins::SettingSchemaLoader.load(manifest)

    assert_equal "config/settings.yml", manifest.settings_contribution_path
    assert_equal "acme/settings", schema.plugin_id
    assert_equal "1", schema.version
    assert_match(/\A[0-9a-f]{64}\z/, schema.digest)
    assert_equal(
      {
        "enabled" => true,
        "endpoint" => "https://api.example.test",
        "mode" => "safe",
        "timeout_seconds" => 10
      },
      schema.defaults
    )
    assert_equal [ "api_token" ], schema.sensitive_keys
    assert_predicate schema, :frozen?
    assert_predicate schema.properties, :frozen?
    assert_predicate schema.properties.fetch("endpoint"), :frozen?
    assert_predicate schema.to_h, :frozen?

    changed_format = valid_document.deep_merge(
      "schema" => { "properties" => { "endpoint" => { "format" => "uri" } } }
    )
    refute_equal(
      schema.digest,
      Mcweb::Plugins::SettingSchema.new(
        plugin_id: "acme/settings",
        document: changed_format
      ).digest
    )
  end

  test "value validation rejects unknown fields wrong types invalid formats and missing required values" do
    schema = Mcweb::Plugins::SettingSchema.new(
      plugin_id: "acme/settings",
      document: valid_document
    )

    values = schema.defaults.merge("api_token" => "secret-value")
    assert_equal values, schema.validate_values(values)
    assert_predicate schema.validate_values(values), :frozen?

    failures = [
      values.merge("unknown" => true),
      values.merge("timeout_seconds" => "10"),
      values.merge("endpoint" => "javascript:alert(1)"),
      values.except("api_token"),
      values.merge("mode" => "undeclared")
    ]
    failures.each do |candidate|
      error = assert_raises(Mcweb::Plugins::SettingValidationError) do
        schema.validate_values(candidate)
      end
      assert_equal "validation_failed", error.code
      refute_includes error.message, "secret-value"
    end
  end

  test "schema declarations reject unknown keywords writable additional properties and unsafe secrets" do
    invalid_documents = []
    invalid_documents << valid_document.deep_merge(
      "schema" => { "properties" => { "enabled" => { "unknown" => true } } }
    )
    invalid_documents << valid_document.deep_merge(
      "schema" => { "additionalProperties" => true }
    )
    invalid_documents << valid_document.deep_merge(
      "schema" => {
        "properties" => {
          "api_token" => { "default" => "must-not-ship" }
        }
      }
    )
    invalid_documents << valid_document.deep_merge(
      "schema" => {
        "properties" => {
          "endpoint" => { "x-mcweb-title-phrase" => "other.plugin.settings.endpoint.title" }
        }
      }
    )
    invalid_documents << valid_document.merge("unknown" => true)
    invalid_documents << valid_document.deep_merge(
      "schema" => { "properties" => { "enabled" => { "minLength" => 0 } } }
    )
    invalid_documents << valid_document.deep_merge(
      "schema" => { "properties" => { "endpoint" => { "minimum" => 0 } } }
    )

    invalid_documents.each do |document|
      assert_raises(Mcweb::Plugins::ManifestError) do
        Mcweb::Plugins::SettingSchema.new(
          plugin_id: "acme/settings",
          document:
        )
      end
    end
  end

  test "hostname format rejects an empty value" do
    document = valid_document.deep_merge(
      "schema" => {
        "properties" => {
          "endpoint" => {
            "default" => "api.example.test",
            "format" => "hostname",
            "x-mcweb-input" => "text"
          }
        }
      }
    )
    schema = Mcweb::Plugins::SettingSchema.new(
      plugin_id: "acme/settings",
      document:
    )

    error = assert_raises(Mcweb::Plugins::SettingValidationError) do
      schema.validate_values(
        schema.defaults.merge(
          "endpoint" => "",
          "api_token" => "secret"
        )
      )
    end

    assert_equal [ "does not match the declared format" ], error.errors.fetch("endpoint")
  end

  test "property regex timeout becomes a stable validation error without echoing the value" do
    document = valid_document.deep_merge(
      "schema" => {
        "properties" => {
          "probe" => {
            "type" => "string",
            "pattern" => "(a+)+\\z",
            "x-mcweb-title-phrase" => "acme.settings.settings.probe.title",
            "x-mcweb-group" => "general"
          }
        }
      }
    )
    schema = Mcweb::Plugins::SettingSchema.new(
      plugin_id: "acme/settings",
      document:
    )
    hostile_value = ("a" * 200_000) + "!"

    error = assert_raises(Mcweb::Plugins::SettingValidationError) do
      schema.validate_values(
        schema.defaults.merge(
          "api_token" => "secret",
          "probe" => hostile_value
        )
      )
    end

    assert_equal "validation_failed", error.code
    assert_equal [ "does not match the declared pattern" ], error.errors.fetch("probe")
    refute_includes error.message, hostile_value
  end

  test "loader rejects duplicate YAML keys before constructing the schema" do
    manifest = write_plugin(valid_document)
    settings_path = Pathname(manifest.source_path).dirname.join("config/settings.yml")
    File.write(
      settings_path,
      <<~YAML
        schema_version: "1"
        schema_version: "2"
        schema: {}
        groups: {}
      YAML
    )

    error = assert_raises(Mcweb::Plugins::ManifestError) do
      Mcweb::Plugins::SettingSchemaLoader.load(manifest)
    end
    assert_includes error.message, "duplicate settings contribution key"
  end

  test "declarative migrations form a complete forward-only path and validate final values" do
    document = valid_document(version: "3").merge(
      "migrations" => [
        {
          "from" => "1",
          "to" => "2",
          "rename" => { "url" => "endpoint" },
          "remove" => [ "legacy_debug" ],
          "defaults" => {}
        },
        {
          "from" => "2",
          "to" => "3",
          "rename" => {},
          "remove" => [],
          "defaults" => {
            "enabled" => true,
            "mode" => "safe",
            "timeout_seconds" => 10
          }
        }
      ]
    )
    schema = Mcweb::Plugins::SettingSchema.new(
      plugin_id: "acme/settings",
      document:
    )

    migrated = schema.migrate(
      {
        "url" => "https://api.example.test",
        "api_token" => "secret",
        "legacy_debug" => true
      },
      from_version: "1"
    )

    assert_equal "https://api.example.test", migrated.fetch("endpoint")
    assert_equal "secret", migrated.fetch("api_token")
    refute_includes migrated, "legacy_debug"
    assert_equal true, migrated.fetch("enabled")

    broken = document.merge(
      "migrations" => [
        {
          "from" => "1",
          "to" => "2",
          "rename" => {},
          "remove" => [ "legacy" ],
          "defaults" => {}
        }
      ]
    )
    assert_raises(Mcweb::Plugins::ManifestError) do
      Mcweb::Plugins::SettingSchema.new(
        plugin_id: "acme/settings",
        document: broken
      )
    end
  end

  private

  def valid_document(version: "1")
    {
      "schema_version" => version,
      "groups" => {
        "general" => {
          "title_phrase" => "acme.settings.settings.groups.general.title",
          "description_phrase" => "acme.settings.settings.groups.general.description",
          "position" => 10
        },
        "credentials" => {
          "title_phrase" => "acme.settings.settings.groups.credentials.title",
          "position" => 20
        }
      },
      "schema" => {
        "$schema" => Mcweb::Plugins::SettingSchema::DRAFT_URI,
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[endpoint api_token],
        "properties" => {
          "enabled" => {
            "type" => "boolean",
            "default" => true,
            "x-mcweb-title-phrase" => "acme.settings.settings.enabled.title",
            "x-mcweb-group" => "general"
          },
          "endpoint" => {
            "type" => "string",
            "default" => "https://api.example.test",
            "format" => "url",
            "maxLength" => 2_048,
            "x-mcweb-title-phrase" => "acme.settings.settings.endpoint.title",
            "x-mcweb-description-phrase" => "acme.settings.settings.endpoint.description",
            "x-mcweb-group" => "general",
            "x-mcweb-input" => "url"
          },
          "mode" => {
            "type" => "string",
            "default" => "safe",
            "enum" => %w[safe fast],
            "x-mcweb-enum-phrases" => {
              "safe" => "acme.settings.settings.mode.safe",
              "fast" => "acme.settings.settings.mode.fast"
            },
            "x-mcweb-title-phrase" => "acme.settings.settings.mode.title",
            "x-mcweb-group" => "general"
          },
          "timeout_seconds" => {
            "type" => "integer",
            "default" => 10,
            "minimum" => 1,
            "maximum" => 120,
            "x-mcweb-title-phrase" => "acme.settings.settings.timeout.title",
            "x-mcweb-group" => "general"
          },
          "api_token" => {
            "type" => "string",
            "minLength" => 1,
            "maxLength" => 4_096,
            "x-mcweb-title-phrase" => "acme.settings.settings.api_token.title",
            "x-mcweb-group" => "credentials",
            "x-mcweb-sensitive" => true,
            "x-mcweb-input" => "password"
          }
        }
      },
      "migrations" => []
    }
  end

  def write_plugin(document)
    directory = @root.join("acme-settings")
    FileUtils.mkdir_p(directory.join("config"))
    File.write(directory.join("config/settings.yml"), YAML.dump(document))
    File.write(
      directory.join("mcweb_plugin.yml"),
      YAML.dump(
        "id" => "acme/settings",
        "name" => "Settings",
        "version" => "1.0.0",
        "api_version" => "1",
        "contributions" => { "settings" => "config/settings.yml" }
      )
    )
    Mcweb::Plugins::Manifest.load_file(directory.join("mcweb_plugin.yml"))
  end
end
