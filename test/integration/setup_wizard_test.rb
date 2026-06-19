# frozen_string_literal: true

require "test_helper"

class SetupWizardIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    InstallationLock.unlock!
    SiteSetting.where(key: %w[site.name site.url]).delete_all
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
    patch setup_step_path("site"), params: { setup: { name: "My Server", url: "https://mc.example.com" } }
    assert_redirected_to setup_step_path("admin")

    assert_difference "User.count", 1 do
      patch setup_step_path("admin"), params: {
        setup: {
          email: "owner@example.com",
          username: "owner",
          display_name: "Owner",
          password: "secret12",
          password_confirmation: "secret12"
        }
      }
    end

    assert_redirected_to identity_sign_in_path
    assert InstallationLock.locked?
    user = User.find_by!(email: "owner@example.com")
    assert user.roles.exists?(key: "super_admin")
    follow_redirect!
    assert_response :success
  end

  test "rejects admin step without password" do
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
end
