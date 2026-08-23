# frozen_string_literal: true

module Mcweb
  class TestDatabaseConnection < ApplicationService
    DATABASE_NAME_PATTERN = /\A[a-zA-Z0-9_]+\z/
    MISSING_PASSWORD = Object.new.freeze

    def initialize(host: nil, port: nil, username: nil, password: MISSING_PASSWORD, database:)
      @host = host.to_s.strip
      @port = port.to_s.strip
      @username = username.to_s.strip
      @password_supplied = !password.equal?(MISSING_PASSWORD) && password.is_a?(String)
      @password = password.to_s if @password_supplied
      @database = database.to_s.strip
    end

    def call
      unless @password_supplied
        return ServiceResult.failure(error: I18n.t("mcweb.setup.database_password_field_missing"))
      end
      return ServiceResult.failure(error: I18n.t("mcweb.setup.database_name_invalid")) unless @database.match?(DATABASE_NAME_PATTERN)
      unless valid_port?
        return ServiceResult.failure(error: I18n.t("mcweb.setup.database_port_invalid"))
      end
      if @host.present? && !Mcweb::DatabaseHostSafety.allowed?(@host)
        return ServiceResult.failure(error: I18n.t("mcweb.setup.database_host_not_allowed"))
      end

      admin = PG.connect(**connection_options("postgres"))
      ensure_database!(admin)
      admin.close

      target = PG.connect(**connection_options(@database))
      target.close

      ServiceResult.success
    rescue PG::Error => e
      Rails.logger.warn("[setup.database] PostgreSQL connection probe failed (#{e.class})")
      ServiceResult.failure(error: I18n.t("mcweb.setup.database_connection_failed_safe"))
    end

    private

    def valid_port?
      return true if @port.blank?
      return false unless @port.match?(/\A\d+\z/)

      (1..65_535).cover?(@port.to_i)
    end

    def connection_options(database)
      {
        host: @host.presence,
        port: @port.present? ? @port.to_i : nil,
        user: @username.presence,
        password: @password,
        dbname: database
      }.compact
    end

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
