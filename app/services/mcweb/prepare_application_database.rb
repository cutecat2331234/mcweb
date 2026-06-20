# frozen_string_literal: true

module Mcweb
  class PrepareApplicationDatabase < ApplicationService
    def call
      Mcweb::LocalConfig.reload!
      reconnect!
      run_db_prepare!
      ServiceResult.success
    rescue StandardError => e
      ServiceResult.failure(error: e.message)
    end

    private

    def reconnect!
      settings = Mcweb::LocalConfig.database_settings_for(Rails.env)
      raise "Missing database configuration for #{Rails.env}" if settings["database"].blank?

      ActiveRecord::Base.establish_connection(
        adapter: "postgresql",
        encoding: "unicode",
        host: settings["host"],
        port: settings["port"],
        username: settings["username"],
        password: settings["password"],
        database: settings["database"]
      )
    end

    def run_db_prepare!
      Rails.application.load_tasks
      Rake::Task["db:prepare"].reenable
      Rake::Task["db:prepare"].invoke
    end
  end
end
