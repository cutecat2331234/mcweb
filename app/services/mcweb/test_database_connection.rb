# frozen_string_literal: true

module Mcweb
  class TestDatabaseConnection < ApplicationService
    DATABASE_NAME_PATTERN = /\A[a-zA-Z0-9_]+\z/

    def initialize(host:, port:, username:, password:, database:)
      @host = host.to_s.strip
      @port = port.to_i
      @username = username.to_s.strip
      @password = password.to_s
      @database = database.to_s.strip
    end

    def call
      return ServiceResult.failure(error: I18n.t("mcweb.setup.database_name_invalid")) unless @database.match?(DATABASE_NAME_PATTERN)
      return ServiceResult.failure(error: I18n.t("mcweb.setup.database_host_required")) if @host.blank?
      return ServiceResult.failure(error: I18n.t("mcweb.setup.database_username_required")) if @username.blank?
      unless Mcweb::DatabaseHostSafety.allowed?(@host)
        return ServiceResult.failure(error: I18n.t("mcweb.setup.database_host_not_allowed"))
      end

      admin = PG.connect(
        host: @host,
        port: @port,
        user: @username,
        password: @password,
        dbname: "postgres"
      )
      ensure_database!(admin)
      admin.close

      target = PG.connect(
        host: @host,
        port: @port,
        user: @username,
        password: @password,
        dbname: @database
      )
      target.close

      ServiceResult.success
    rescue PG::Error => e
      ServiceResult.failure(error: I18n.t("mcweb.setup.database_connection_failed", message: e.message))
    end

    private

    def ensure_database!(connection)
      exists = connection.exec_params(
        "SELECT 1 FROM pg_database WHERE datname = $1",
        [ @database ]
      ).ntuples.positive?
      return if exists

      connection.exec("CREATE DATABASE #{quote_identifier(@database)}")
    end

    def quote_identifier(name)
      %("#{name.gsub('"', '""')}")
    end
  end
end
