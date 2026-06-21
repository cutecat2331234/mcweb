# frozen_string_literal: true

module Setup
  class FinalizeInstallation < ApplicationService
    INSTALLATION_FINALIZE_LOCK_KEY = 748_239_013

    def initialize(database:, site:, admin:, ip_address: "127.0.0.1", skip_database: false)
      @database = database.with_indifferent_access
      @site = site.with_indifferent_access
      @admin = admin.with_indifferent_access
      @ip_address = ip_address
      @skip_database = skip_database
    end

    def call
      return ServiceResult.failure(error: "installation already complete") if installation_complete?

      password = @admin[:password].to_s
      return ServiceResult.failure(error: "password required") if password.blank?
      return ServiceResult.failure(error: "password too short") if password.length < 6

      unless @skip_database
        db_result = configure_database!
        return db_result unless db_result.success?
      end

      finalize_admin!
    end

    private

    def installation_complete?
      InstallationLock.locked? || User.exists?(account_type: :owner)
    end

    def configure_database!
      database_name = @database[:development_database].presence ||
        Mcweb::LocalConfig.default_database_name("development")

      test_result = Mcweb::TestDatabaseConnection.call(
        host: @database[:host],
        port: @database[:port],
        username: @database[:username],
        password: @database[:password],
        database: database_name
      )
      return ServiceResult.failure(error: test_result.error) unless test_result.success?

      Mcweb::LocalConfig.write!(
        "database" => {
          "host" => @database[:host],
          "port" => @database[:port].to_i,
          "username" => @database[:username],
          "password" => @database[:password],
          "development" => database_name,
          "test" => @database[:test_database].presence || Mcweb::LocalConfig.default_database_name("test"),
          "production" => @database[:production_database].presence || Mcweb::LocalConfig.default_database_name("production")
        }
      )

      prepare_result = Mcweb::PrepareApplicationDatabase.call
      return prepare_result unless prepare_result.success?

      InstallationLock.unlock!
      ServiceResult.success
    end

    def finalize_admin!
      outcome = :unknown
      register_error = nil
      user = nil

      ActiveRecord::Base.transaction do
        acquire_installation_finalize_lock!

        if InstallationLock.locked? || User.exists?(account_type: :owner)
          outcome = :already_complete
          next
        end

        result = Identity::RegisterUser.call(
          email: @admin[:email],
          username: @admin[:username],
          password: @admin[:password],
          display_name: @admin[:display_name],
          ip_address: @ip_address
        )

        unless result.success?
          outcome = :register_failed
          register_error = result.error || result.errors&.values&.flatten&.first
          raise ActiveRecord::Rollback
        end

        user = result.value[:user]
        user.update!(email_verified: true, email_verified_at: Time.current, account_type: :owner)

        Rails.application.load_seed unless Role.exists?(key: "owner")
        admin_role = Role.find_by!(key: "owner")
        user.roles << admin_role unless user.roles.include?(admin_role)

        SiteSetting.set("site.name", @site[:name]) if @site[:name].present?
        SiteSetting.set("site.url", @site[:url]) if @site[:url].present?

        InstallationLock.lock!(user: user)
        outcome = :success
      end

      case outcome
      when :already_complete
        ServiceResult.success({ message: "already complete" })
      when :register_failed
        ServiceResult.failure(error: register_error)
      when :success
        Frontend::EnsureDefaultTemplate.call
        ServiceResult.success({ user: user, message: "installation complete" })
      else
        ServiceResult.failure(error: "unknown finalize outcome")
      end
    end

    def acquire_installation_finalize_lock!
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array([ "SELECT pg_advisory_xact_lock(?)", INSTALLATION_FINALIZE_LOCK_KEY ])
      )
    end
  end
end
