# frozen_string_literal: true

require "test_helper"

module Admin
  module System
    class SystemBansPermissionsAdminTest < ActionDispatch::IntegrationTest
      setup do
        @staff = create_user(account_type: "staff")
        grant_permission(@staff, "admin.access")
        grant_admin_module(@staff, "system")
        sign_in_as(@staff)
      end

      test "admin access alone cannot read or create IP and email bans" do
        get admin_system_ip_bans_path
        assert_redirected_to root_path

        assert_no_difference -> { Administration::IpBan.count } do
          post admin_system_ip_bans_path, params: { ip_address: "198.51.100.42", reason: "abuse" }
        end
        assert_redirected_to root_path

        get admin_system_email_bans_path
        assert_redirected_to root_path

        assert_no_difference -> { Administration::EmailBan.count } do
          post admin_system_email_bans_path, params: {
            email_ban: { pattern: "*@blocked.test", reason: "abuse" }
          }
        end
        assert_redirected_to root_path
      end

      test "system bans permission authorizes IP and email ban lifecycle" do
        grant_permission(@staff, "system.bans.manage")

        get admin_system_ip_bans_path
        assert_response :success

        assert_difference -> { Administration::IpBan.count }, 1 do
          post admin_system_ip_bans_path, params: { ip_address: "198.51.100.43", reason: "abuse" }
        end
        assert_redirected_to admin_system_ip_bans_path

        ip_ban = Administration::IpBan.find_by!(ip_address: "198.51.100.43")
        assert_difference -> { Administration::IpBan.count }, -1 do
          delete admin_system_ip_ban_path(ip_ban)
        end
        assert_redirected_to admin_system_ip_bans_path

        get admin_system_email_bans_path
        assert_response :success

        assert_difference -> { Administration::EmailBan.count }, 1 do
          post admin_system_email_bans_path, params: {
            email_ban: { pattern: "*@allowed.test", reason: "abuse" }
          }
        end
        assert_redirected_to admin_system_email_bans_path

        email_ban = Administration::EmailBan.find_by!(pattern: "*@allowed.test")
        assert_difference -> { Administration::EmailBan.count }, -1 do
          delete admin_system_email_ban_path(email_ban)
        end
        assert_redirected_to admin_system_email_bans_path
      end
    end
  end
end
