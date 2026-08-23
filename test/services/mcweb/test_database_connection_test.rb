# frozen_string_literal: true

require "test_helper"

class Mcweb::TestDatabaseConnectionTest < ActiveSupport::TestCase
  FakeResult = Struct.new(:ntuples)

  class FakeConnection
    attr_reader :closed

    def exec_params(*)
      FakeResult.new(1)
    end

    def close
      @closed = true
    end
  end

  test "uses libpq defaults while retaining an explicitly blank password" do
    options = []
    connections = [ FakeConnection.new, FakeConnection.new ]

    PG.stub(:connect, ->(**value) { options << value; connections.shift }) do
      result = Mcweb::TestDatabaseConnection.call(
        host: "",
        port: "",
        username: "",
        password: "",
        database: "mcweb_development"
      )

      assert result.success?
    end

    assert_equal(
      [
        { password: "", dbname: "postgres" },
        { password: "", dbname: "mcweb_development" }
      ],
      options
    )
  end

  test "rejects a missing password keyword before connecting" do
    PG.stub(:connect, ->(**) { flunk("connection must not be attempted") }) do
      result = Mcweb::TestDatabaseConnection.call(database: "mcweb_development")

      assert result.failure?
      assert_equal I18n.t("mcweb.setup.database_password_field_missing"), result.error
    end
  end

  test "rejects a null password instead of converting it to an empty string" do
    PG.stub(:connect, ->(**) { flunk("connection must not be attempted") }) do
      result = Mcweb::TestDatabaseConnection.call(
        password: nil,
        database: "mcweb_development"
      )

      assert result.failure?
      assert_equal I18n.t("mcweb.setup.database_password_field_missing"), result.error
    end
  end

  test "preserves explicit password based TCP options" do
    options = []
    connections = [ FakeConnection.new, FakeConnection.new ]

    PG.stub(:connect, ->(**value) { options << value; connections.shift }) do
      result = Mcweb::TestDatabaseConnection.call(
        host: "127.0.0.1",
        port: "5432",
        username: "mcweb",
        password: " database secret ",
        database: "mcweb_development"
      )

      assert result.success?
    end

    assert_equal " database secret ", options.first.fetch(:password)
    assert_equal "127.0.0.1", options.first.fetch(:host)
    assert_equal 5432, options.first.fetch(:port)
    assert_equal "mcweb", options.first.fetch(:user)
  end

  test "does not reflect PostgreSQL exception details" do
    leaked_detail = "password=private-token host=database.internal dbname=secret_database"

    PG.stub(:connect, ->(**) { raise PG::ConnectionBad, leaked_detail }) do
      result = Mcweb::TestDatabaseConnection.call(
        host: "127.0.0.1",
        port: 5432,
        username: "mcweb",
        password: "private-token",
        database: "mcweb_development"
      )

      assert result.failure?
      assert_equal I18n.t("mcweb.setup.database_connection_failed_safe"), result.error
      refute_includes result.error, "private-token"
      refute_includes result.error, "database.internal"
      refute_includes result.error, "secret_database"
    end
  end

  test "rejects an invalid explicit port before connecting" do
    PG.stub(:connect, ->(**) { flunk("connection must not be attempted") }) do
      result = Mcweb::TestDatabaseConnection.call(
        port: "65536",
        password: "",
        database: "mcweb_development"
      )

      assert result.failure?
      assert_equal I18n.t("mcweb.setup.database_port_invalid"), result.error
    end
  end
end
