# frozen_string_literal: true

require "test_helper"

class SetupWizardIntegrationTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  self.use_transactional_tests = false

  setup do
    @local_config_path = Rails.root.join("tmp", "test-local-#{Process.pid}-#{SecureRandom.hex(4)}.yml")
    ENV["MCWEB_LOCAL_CONFIG_PATH"] = @local_config_path.to_s
    Mcweb::LocalConfig.reload!

    InstallationLock.unlock!
    User.where(account_type: "owner").update_all(account_type: "member")
    SiteSetting.where(key: %w[site.name site.url]).delete_all
    @owner_email = "owner-#{SecureRandom.hex(4)}@example.com"
  end

  teardown do
    User.where(account_type: "owner").update_all(account_type: "member")
    ensure_installation_locked!
    FileUtils.rm_f(@local_config_path)
    ENV.delete("MCWEB_LOCAL_CONFIG_PATH")
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

  test "completes setup when admin step submits password" do
    unlock_for_setup!
    patch setup_step_path("database"), params: {
      setup: {
        host: "127.0.0.1",
        port: 5432,
        username: db_username,
        password: db_password,
        development_database: "mcweb_test"
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
        host: "127.0.0.1",
        port: 5432,
        username: db_username,
        password: db_password,
        development_database: "mcweb_test"
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
    patch setup_step_path("admin"), params: {
      setup: {
        email: "attacker@example.com",
        username: "attacker",
        display_name: "Attacker",
        password: "secret12",
        password_confirmation: "secret12"
      }
    }

    assert_redirected_to root_path
    assert_equal I18n.t("mcweb.flash.installation_locked"), flash[:alert]
  end

  test "rejects admin step without password" do
    unlock_for_setup!
    patch setup_step_path("database"), params: {
      setup: {
        host: "127.0.0.1",
        port: 5432,
        username: db_username,
        password: db_password,
        development_database: "mcweb_test"
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

  def db_password
    ActiveRecord::Base.connection_db_config.configuration_hash[:password].to_s
  end
end
