# frozen_string_literal: true

require "test_helper"

class Mcweb::PasswordlessDatabaseContractTest < ActiveSupport::TestCase
  test "normalizes socket defaults without losing an explicit blank password" do
    configuration = Mcweb::LocalConfig.normalized_database_configuration(
      {
        host: " ",
        port: "",
        username: " ",
        password: "",
        test_database: "socket_test"
      },
      development_database: "socket_development"
    )

    assert_not configuration.key?("host")
    assert_not configuration.key?("port")
    assert_not configuration.key?("username")
    assert configuration.key?("password")
    assert_equal "", configuration.fetch("password")
    assert_equal "socket_development", configuration.fetch("development")
    assert_equal "socket_test", configuration.fetch("test")
  end

  test "normalization keeps a missing password missing" do
    configuration = Mcweb::LocalConfig.normalized_database_configuration(
      {},
      development_database: "mcweb_development"
    )

    assert_not configuration.key?("password")
  end

  test "normalization does not convert a null password to an empty string" do
    configuration = Mcweb::LocalConfig.normalized_database_configuration(
      { password: nil },
      development_database: "mcweb_development"
    )

    assert_not configuration.key?("password")
  end

  test "local configuration does not treat a null password as complete" do
    Mcweb::LocalConfig.stub(:load, {
      "database" => { "password" => nil },
      "secret_key_base" => "secret",
      "lockbox_master_key" => "lockbox"
    }) do
      assert_not Mcweb::LocalConfig.complete?
    end
  end

  test "runtime settings retain an explicit blank password key" do
    settings = Mcweb::LocalConfig.database_settings_for(
      "production",
      environment: {
        "MCWEB_DATABASE_HOST" => "database.internal",
        "MCWEB_DATABASE_PORT" => "5432",
        "MCWEB_DATABASE_USERNAME" => "mcweb",
        "MCWEB_DATABASE_PASSWORD" => "",
        "MCWEB_DATABASE_NAME" => "mcweb_production"
      }
    )

    assert settings.key?("password")
    assert_equal "", settings.fetch("password")
  end

  test "production foundation accepts explicit blank and rejects missing password" do
    base = {
      "SECRET_KEY_BASE" => "s" * 128,
      "LOCKBOX_MASTER_KEY" => "a" * 64,
      "MCWEB_DATABASE_HOST" => "database.internal",
      "MCWEB_DATABASE_USERNAME" => "mcweb"
    }

    assert Mcweb::ProductionEnvironment.validate_foundation!(
      base.merge("MCWEB_DATABASE_PASSWORD" => "")
    )

    error = assert_raises(Mcweb::ProductionEnvironment::InvalidConfiguration) do
      Mcweb::ProductionEnvironment.validate_foundation!(base)
    end
    assert_includes error.message, "MCWEB_DATABASE_PASSWORD"

    error = assert_raises(Mcweb::ProductionEnvironment::InvalidConfiguration) do
      Mcweb::ProductionEnvironment.validate_foundation!(
        base.merge("MCWEB_DATABASE_PASSWORD" => nil)
      )
    end
    assert_includes error.message, "MCWEB_DATABASE_PASSWORD"
  end

  test "database preparation omits socket defaults and retains blank password" do
    captured = nil
    settings = {
      "password" => "",
      "database" => "mcweb_development"
    }
    service = Mcweb::PrepareApplicationDatabase.new

    Mcweb::LocalConfig.stub(:database_settings_for, settings) do
      ActiveRecord::Base.stub(:establish_connection, ->(options) { captured = options }) do
        service.send(:reconnect!)
      end
    end

    assert_equal(
      {
        adapter: "postgresql",
        encoding: "unicode",
        database: "mcweb_development",
        password: ""
      },
      captured
    )
  end

  test "database preparation returns a non reflective error" do
    service = Mcweb::PrepareApplicationDatabase.new
    leaked_detail = "postgresql://mcweb:private-token@database.internal/secret_database"

    Mcweb::LocalConfig.stub(:reload!, -> { raise RuntimeError, leaked_detail }) do
      result = service.call

      assert result.failure?
      assert_equal I18n.t("mcweb.setup.database_prepare_failed_safe"), result.error
      refute_includes result.error, "private-token"
      refute_includes result.error, "database.internal"
      refute_includes result.error, "secret_database"
    end
  end
end
