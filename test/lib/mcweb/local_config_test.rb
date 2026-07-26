# frozen_string_literal: true

require "test_helper"

class Mcweb::LocalConfigTest < ActiveSupport::TestCase
  setup do
    @tmpdir = Dir.mktmpdir
    @original_path = ENV["MCWEB_LOCAL_CONFIG_PATH"]
    ENV["MCWEB_LOCAL_CONFIG_PATH"] = File.join(@tmpdir, "local.yml")
    Mcweb::LocalConfig.reload!
  end

  teardown do
    if @original_path
      ENV["MCWEB_LOCAL_CONFIG_PATH"] = @original_path
    else
      ENV.delete("MCWEB_LOCAL_CONFIG_PATH")
    end
    Mcweb::LocalConfig.reload!
    Pathname(@tmpdir).rmtree if @tmpdir && Pathname(@tmpdir).exist?
  end

  test "exist? is false until file is written" do
    assert_not Mcweb::LocalConfig.exist?
  end

  test "write! persists database and secrets" do
    Mcweb::LocalConfig.write!(
      database: {
        host: "127.0.0.1",
        port: 5432,
        username: "mcweb",
        password: "secret",
        development: "mcweb_development"
      }
    )

    assert Mcweb::LocalConfig.exist?
    assert Mcweb::LocalConfig.complete?
    assert_equal "127.0.0.1", Mcweb::LocalConfig.load.dig("database", "host")
    assert Mcweb::LocalConfig.load["secret_key_base"].present?
    assert Mcweb::LocalConfig.load["lockbox_master_key"].present?
  end

  test "database_settings_for returns env-specific database name" do
    Mcweb::LocalConfig.write!(
      database: {
        host: "127.0.0.1",
        username: "mcweb",
        password: "secret",
        development: "custom_dev",
        test: "custom_test"
      }
    )

    settings = Mcweb::LocalConfig.database_settings_for("development")
    assert_equal "custom_dev", settings["database"]
    assert_equal "127.0.0.1", settings["host"]
  end

  test "production database environment overrides local secrets without affecting development" do
    Mcweb::LocalConfig.write!(
      database: {
        host: "local-db",
        username: "local-user",
        password: "local-secret",
        development: "custom_dev",
        production: "local_production"
      }
    )
    environment = {
      "MCWEB_DATABASE_HOST" => "production-db",
      "MCWEB_DATABASE_PORT" => "5433",
      "MCWEB_DATABASE_USERNAME" => "production-user",
      "MCWEB_DATABASE_PASSWORD" => "production-secret",
      "MCWEB_DATABASE_NAME" => "production-name"
    }

    production = Mcweb::LocalConfig.database_settings_for(
      "production",
      environment: environment
    )
    development = Mcweb::LocalConfig.database_settings_for(
      "development",
      environment: environment
    )

    assert_equal(
      {
        "host" => "production-db",
        "port" => "5433",
        "username" => "production-user",
        "password" => "production-secret",
        "database" => "production-name"
      },
      production
    )
    assert_equal "local-db", development["host"]
    assert_equal "custom_dev", development["database"]
  end
end
