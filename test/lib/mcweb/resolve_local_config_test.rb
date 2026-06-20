# frozen_string_literal: true

require "test_helper"
require "mcweb/resolve_local_config"

class Mcweb::ResolveLocalConfigTest < ActiveSupport::TestCase
  setup do
    @tmpdir = Dir.mktmpdir
    @config_path = Pathname(@tmpdir).join("local.yml")
    @example_path = Pathname(@tmpdir).join("local.yml.example")
    @example_path.write(<<~YAML)
      database:
        host: 127.0.0.1
        port: 5432
        username: example
        password: example
        development: mcweb_development
      secret_key_base: example
      lockbox_master_key: example
    YAML
  end

  teardown do
    Pathname(@tmpdir).rmtree if @tmpdir && Pathname(@tmpdir).exist?
  end

  test "returns existing config without overwriting" do
    @config_path.write("database:\n  host: kept\n")

    result = Mcweb::ResolveLocalConfig.call(
      config_path: @config_path.to_s,
      example_path: @example_path.to_s,
      server_root: nil
    )

    assert_equal :existing, result.source
    assert_not result.created
    assert_includes @config_path.read, "kept"
  end

  test "copies example when no server database.yml" do
    result = Mcweb::ResolveLocalConfig.call(
      config_path: @config_path.to_s,
      example_path: @example_path.to_s,
      server_root: nil
    )

    assert_equal :example, result.source
    assert result.created
    assert @config_path.exist?
    assert_includes @config_path.read, "mcweb_development"
  end

  test "imports database settings from server config/database.yml" do
    server_root = Pathname(@tmpdir).join("server")
    db_yml = server_root.join("config", "database.yml")
    db_yml.dirname.mkpath
    db_yml.write(<<~YAML)
      development:
        host: 10.0.0.5
        port: 5433
        username: mcweb
        password: secret
        database: mcweb_from_server
    YAML

    result = Mcweb::ResolveLocalConfig.call(
      config_path: @config_path.to_s,
      example_path: @example_path.to_s,
      server_root: server_root,
      env: "development"
    )

    assert_equal :database_yml, result.source
    data = YAML.safe_load_file(@config_path)
    assert_equal "10.0.0.5", data.dig("database", "host")
    assert_equal 5433, data.dig("database", "port")
    assert_equal "mcweb", data.dig("database", "username")
    assert_equal "secret", data.dig("database", "password")
    assert_equal "mcweb_from_server", data.dig("database", "development")
    assert data["secret_key_base"].present?
    assert data["lockbox_master_key"].present?
    assert_equal "redis://127.0.0.1:6379/0", data["redis_url"]
    assert_equal 5, data["job_concurrency"]
  end
end
