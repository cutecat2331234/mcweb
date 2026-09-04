# frozen_string_literal: true

require "test_helper"

class SetupWizardIntegrationTest < ActionDispatch::IntegrationTest
  SITE_SETTING_KEYS = %w[site.name site.url].freeze
  DURABLE_LEDGER_IMMUTABLE_TRIGGERS = {
    "operations_durable_enqueue_events" => "operations_durable_events_immutable",
    "operations_durable_enqueue_attempts" => "operations_durable_attempts_immutable",
    "operations_durable_enqueue_intents" => "operations_durable_intents_immutable"
  }.freeze

  parallelize(workers: 1)

  self.use_transactional_tests = false

  setup do
    @original_database_url = ENV.delete("DATABASE_URL")
    @original_local_config_path = ENV["MCWEB_LOCAL_CONFIG_PATH"]
    @local_config_path = Rails.root.join("tmp", "test-local-#{Process.pid}-#{SecureRandom.hex(4)}.yml")
    ENV["MCWEB_LOCAL_CONFIG_PATH"] = @local_config_path.to_s
    Mcweb::LocalConfig.reload!
    @test_database_name = ActiveRecord::Base.connection_db_config.database
    @installation_lock_snapshot = InstallationLock.order(:id).map(&:attributes)
    @site_setting_snapshot = SiteSetting.where(key: SITE_SETTING_KEYS).order(:id).map(&:attributes)
    @owner_ids = User.where(account_type: "owner").pluck(:id)
    @existing_user_ids = User.pluck(:id)

    InstallationLock.unlock!
    User.where(account_type: "owner").update_all(account_type: "member")
    SiteSetting.where(key: SITE_SETTING_KEYS).delete_all
    @owner_email = "owner-#{SecureRandom.hex(4)}@example.com"
  end

  teardown do
    # database step 会经 Mcweb::PrepareApplicationDatabase 重连全局连接池，先恢复测试库连接再清理
    ActiveRecord::Base.establish_connection(:test)
    restore_persisted_setup_state!
    FileUtils.rm_f(@local_config_path)
    restore_environment("DATABASE_URL", @original_database_url)
    restore_environment("MCWEB_LOCAL_CONFIG_PATH", @original_local_config_path)
    Mcweb::LocalConfig.reload!
  end

  test "redirects uninstalled visitors to setup" do
    get identity_sign_in_path
    assert_redirected_to setup_root_path

    get root_path
    assert_redirected_to setup_root_path

    get store_products_path
    assert_redirected_to setup_root_path
  end

  test "database form allows libpq defaults and an intentionally empty password" do
    unlock_for_setup!

    get setup_step_path("database")

    assert_response :success
    %w[host port username password].each do |field|
      assert_select "#setup_#{field}"
      assert_select "#setup_#{field}[required]", count: 0
    end
  end

  test "database step preserves an explicitly empty password" do
    unlock_for_setup!
    connection_options = []
    connection_check = lambda do |**options|
      connection_options << options
      ServiceResult.success
    end

    Mcweb::TestDatabaseConnection.stub(:call, connection_check) do
      Mcweb::PrepareApplicationDatabase.stub(:call, ServiceResult.success) do
        patch setup_step_path("database"), params: {
          setup: {
            host: db_host,
            port: 5432,
            username: "postgres",
            password: "",
            development_database: "mcweb_passwordless"
          }
        }
      end
    end

    assert_redirected_to setup_step_path("site")
    assert_equal "", connection_options.sole.fetch(:password)
    assert_equal "", Mcweb::LocalConfig["database", "password"]
  end

  test "database step preserves passwordless socket defaults" do
    unlock_for_setup!
    connection_options = []
    connection_check = lambda do |**options|
      connection_options << options
      ServiceResult.success
    end

    Mcweb::TestDatabaseConnection.stub(:call, connection_check) do
      Mcweb::PrepareApplicationDatabase.stub(:call, ServiceResult.success) do
        patch setup_step_path("database"), params: {
          setup: {
            host: "",
            port: "",
            username: "",
            password: "",
            development_database: "mcweb_socket"
          }
        }
      end
    end

    assert_redirected_to setup_step_path("site")
    submitted = connection_options.sole
    assert_equal "", submitted.fetch(:host)
    assert_equal "", submitted.fetch(:port)
    assert_equal "", submitted.fetch(:username)
    assert_equal "", submitted.fetch(:password)
    assert_not Mcweb::LocalConfig.load.fetch("database").key?("host")
    assert_not Mcweb::LocalConfig.load.fetch("database").key?("port")
    assert_not Mcweb::LocalConfig.load.fetch("database").key?("username")
    assert_equal "", Mcweb::LocalConfig["database", "password"]
  end

  test "database step rejects a missing password field without testing a connection" do
    unlock_for_setup!

    Mcweb::TestDatabaseConnection.stub(:call, ->(**) { flunk("connection must not be tested") }) do
      patch setup_step_path("database"), params: {
        setup: {
          host: db_host,
          port: 5432,
          username: "postgres",
          development_database: "mcweb_missing_password_field"
        }
      }
    end

    assert_redirected_to setup_step_path("database")
    assert_equal I18n.t("mcweb.setup.database_password_field_missing"), flash[:alert]
  end

  test "completes setup when admin step submits password" do
    unlock_for_setup!
    patch setup_step_path("database"), params: {
      setup: {
        host: db_host,
        port: db_port,
        username: db_username,
        password: db_password,
        development_database: @test_database_name,
        test_database: @test_database_name
      }
    }
    assert_redirected_to setup_step_path("site"), flash[:notice]

    unlock_for_setup!
    patch setup_step_path("site"), params: { setup: { name: "My Server", url: "https://mc.example.com" } }
    assert_redirected_to setup_step_path("admin")

    unlock_for_setup!
    assert_difference -> { User.where(account_type: "owner").count }, 1 do
      patch setup_step_path("admin"), params: {
        setup: {
          email: @owner_email,
          username: "owner#{SecureRandom.hex(2)}",
          display_name: "Owner",
          password: "secret12",
          password_confirmation: "secret12"
        }
      }
    end

    assert_redirected_to identity_sign_in_path
    assert InstallationLock.locked?
    user = User.find_by!(email: @owner_email)
    assert user.roles.exists?(key: "owner")
    assert_equal "owner", user.account_type
    follow_redirect!
    assert_response :success
  end

  test "rejects second owner during setup window" do
    unlock_for_setup!
    patch setup_step_path("database"), params: {
      setup: {
        host: db_host,
        port: db_port,
        username: db_username,
        password: db_password,
        development_database: @test_database_name,
        test_database: @test_database_name
      }
    }
    patch setup_step_path("site"), params: { setup: { name: "My Server", url: "https://mc.example.com" } }

    patch setup_step_path("admin"), params: {
      setup: {
        email: @owner_email,
        username: "owner#{SecureRandom.hex(2)}",
        display_name: "Owner",
        password: "secret12",
        password_confirmation: "secret12"
      }
    }
    assert_redirected_to identity_sign_in_path

    reset!
    # Model a stale/reopened setup window: the owner existence check must still
    # be authoritative even when the installation lock is unexpectedly clear.
    InstallationLock.unlock!
    attacker_email = "attacker@example.com"
    assert_no_difference -> { User.where(account_type: "owner").count } do
      patch setup_step_path("admin"), params: {
        setup: {
          email: attacker_email,
          username: "attacker",
          display_name: "Attacker",
          password: "secret12",
          password_confirmation: "secret12"
        }
      }
    end

    assert_redirected_to identity_sign_in_path
    assert_equal I18n.t("mcweb.setup.already_complete"), flash[:alert]
    assert_not User.exists?(email: attacker_email)
  end

  test "rejects admin step without password" do
    unlock_for_setup!
    patch setup_step_path("database"), params: {
      setup: {
        host: db_host,
        port: db_port,
        username: db_username,
        password: db_password,
        development_database: @test_database_name,
        test_database: @test_database_name
      }
    }
    patch setup_step_path("site"), params: { setup: { name: "My Server", url: "https://mc.example.com" } }

    patch setup_step_path("admin"), params: {
      setup: {
        email: "owner@example.com",
        username: "owner",
        password: "",
        password_confirmation: ""
      }
    }

    assert_redirected_to setup_step_path("admin")
    assert_equal I18n.t("mcweb.setup.password_required"), flash[:alert]
  end

  private

  def unlock_for_setup!
    InstallationLock.unlock!
  end

  def db_username
    ActiveRecord::Base.connection_db_config.configuration_hash[:username] || "postgres"
  end

  def db_host
    ActiveRecord::Base.connection_db_config.configuration_hash[:host].presence || "127.0.0.1"
  end

  def db_password
    ActiveRecord::Base.connection_db_config.configuration_hash[:password].to_s
  end

  def db_port
    ActiveRecord::Base.connection_db_config.configuration_hash[:port] || 5432
  end

  def restore_environment(name, value)
    value.nil? ? ENV.delete(name) : ENV[name] = value
  end

  def restore_persisted_setup_state!
    InstallationLock.delete_all
    remove_setup_users!
    User.where(id: @owner_ids).update_all(account_type: "owner")
    InstallationLock.insert_all!(@installation_lock_snapshot) if @installation_lock_snapshot.any?

    SiteSetting.where(key: SITE_SETTING_KEYS).delete_all
    SiteSetting.insert_all!(@site_setting_snapshot) if @site_setting_snapshot.any?
    SITE_SETTING_KEYS.each { |key| Rails.cache.delete(SiteSetting.cache_key(key)) }
  end

  def remove_setup_users!
    users = User.where.not(id: @existing_user_ids)
    user_ids = users.pluck(:id)
    return if user_ids.empty?

    intents = Operations::DurableEnqueueIntent.where(source_kind: "user", source_id: user_ids)
    without_durable_ledger_immutability do
      Operations::DurableEnqueueEvent.where(intent_id: intents.select(:id)).delete_all
      Operations::DurableEnqueueAttempt.where(intent_id: intents.select(:id)).delete_all
      intents.delete_all
    end
    AuditLog.where(actor_id: user_ids).delete_all
    users.find_each(&:destroy!)
  end

  def without_durable_ledger_immutability
    connection = ApplicationRecord.connection
    disabled = []
    DURABLE_LEDGER_IMMUTABLE_TRIGGERS.each do |table, trigger|
      connection.execute(
        "ALTER TABLE #{connection.quote_table_name(table)} " \
        "DISABLE TRIGGER #{connection.quote_column_name(trigger)}"
      )
      disabled << [ table, trigger ]
    end

    yield
  ensure
    disabled&.reverse_each do |table, trigger|
      connection.execute(
        "ALTER TABLE #{connection.quote_table_name(table)} " \
        "ENABLE TRIGGER #{connection.quote_column_name(trigger)}"
      )
    end
  end
end
