# frozen_string_literal: true

module Mcweb
  class PrepareApplicationDatabase < ApplicationService
    def call
      Mcweb::LocalConfig.reload!
      reconnect!
      run_db_prepare!
      ServiceResult.success
    rescue StandardError => e
      Rails.logger.warn("[setup.database] application database preparation failed (#{e.class})")
      ServiceResult.failure(error: I18n.t("mcweb.setup.database_prepare_failed_safe"))
    end

    private

    def reconnect!
      settings = Mcweb::LocalConfig.database_settings_for(Rails.env)
      raise "Missing database configuration for #{Rails.env}" if settings["database"].blank?

      connection_options = {
        adapter: "postgresql",
        encoding: "unicode",
        database: settings["database"]
      }
      %w[host port username password].each do |key|
        connection_options[key.to_sym] = settings[key] if settings.key?(key)
      end

      ActiveRecord::Base.establish_connection(connection_options)
    end

    def run_db_prepare!
      Rails.application.load_tasks
      Rake::Task["db:prepare"].reenable
      Rake::Task["db:prepare"].invoke
    end
  end
end
