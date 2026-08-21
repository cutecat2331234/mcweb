# frozen_string_literal: true

require "test_helper"

class IdentitySecurityLifecycleIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
  end

  test "security page is private and never cacheable" do
    get identity_security_path

    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  test "totp confirmation presents recovery codes once" do
    @user.setup_totp!
    code = ROTP::TOTP.new(@user.totp_secret).now
    first_recovery_code = @user.recovery_codes.first

    post identity_security_totp_confirm_path, params: { totp: { code: code } }

    assert_redirected_to identity_security_path
    follow_redirect!
    assert_response :success
    assert_includes response.body, first_recovery_code

    get identity_security_path
    assert_response :success
    refute_includes response.body, first_recovery_code
  end

  test "recovery code regeneration uses the signed-in flow and exposes replacements once" do
    @user.setup_totp!
    @user.update!(totp_enabled: true)
    old_code = @user.recovery_codes.first

    post identity_security_totp_recovery_codes_path, params: {
      recovery_codes: {
        password: "password123",
        code: ROTP::TOTP.new(@user.totp_secret).now
      }
    }

    assert_redirected_to identity_security_path
    replacement = @user.reload.recovery_codes.first
    refute_equal old_code, replacement
    follow_redirect!
    assert_includes response.body, replacement
  end

  test "email change revokes other sessions and requires replacement verification" do
    other_session = Identity::SessionManager.call(user: @user).value.fetch(:session)
    delivery_enqueued = false

    Mcweb::DeveloperMode.stub(:allow?, false) do
      MailDeliveryJob.stub(:perform_later, ->(*_args, **_kwargs) { delivery_enqueued = true }) do
        patch identity_security_email_path, params: {
          email_change: {
            email: "changed@example.com",
            password: "password123",
            code: ""
          }
        }
      end
    end

    assert_redirected_to identity_security_path
    assert delivery_enqueued
    assert_equal "changed@example.com", @user.reload.email
    refute @user.email_verified?
    assert other_session.reload.revoked?
  end

  test "self-service account closure signs out and anonymizes the member" do
    delete identity_security_account_path, params: {
      account_close: {
        password: "password123",
        code: "",
        confirmation: "DELETE",
        reason: "Leaving"
      }
    }

    assert_redirected_to root_path
    assert @user.reload.deleted?
    assert_not session[:session_token].present?
    assert AuditLog.exists?(action: "identity.account_closed", resource_id: @user.id)
  end
end
