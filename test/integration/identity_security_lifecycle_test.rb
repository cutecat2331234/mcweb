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
    current_session = @user.sessions.active.order(created_at: :desc).first
    original_current_digest = current_session.token_digest
    other_session = create_test_session(@user).value.fetch(:session)
    post identity_security_totp_setup_path
    assert_redirected_to identity_security_path
    @user.reload
    code = ROTP::TOTP.new(@user.totp_secret).now
    first_recovery_code = @user.recovery_codes.first

    post identity_security_totp_confirm_path, params: {
      totp: { password: "password123", code: code }
    }

    assert_redirected_to identity_security_path
    assert @user.reload.totp_enabled?
    assert other_session.reload.revoked?
    refute current_session.reload.revoked?
    refute_equal original_current_digest, current_session.token_digest
    follow_redirect!
    assert_response :success
    assert_includes response.body, first_recovery_code

    get identity_security_path
    assert_response :success
    refute_includes response.body, first_recovery_code
  end

  test "totp confirmation rejects a stolen session without the current password" do
    other_session = create_test_session(@user).value.fetch(:session)
    post identity_security_totp_setup_path
    code = ROTP::TOTP.new(@user.reload.totp_secret).now

    post identity_security_totp_confirm_path, params: {
      totp: { password: "wrong-password", code: code }
    }

    assert_redirected_to identity_security_path
    refute @user.reload.totp_enabled?
    refute other_session.reload.revoked?
    follow_redirect!
    assert_includes response.body, I18n.t("mcweb.services.errors.password_incorrect")
  end

  test "a stale browser cannot enable the secret installed by a newer totp setup" do
    browser_a = open_session
    browser_b = open_session
    [ browser_a, browser_b ].each do |browser|
      browser.post identity_session_path, params: {
        session: {
          email: @user.email,
          password: "password123",
          remember_me: "0"
        }
      }
      assert_equal 302, browser.response.status
    end

    browser_a.post identity_security_totp_setup_path
    assert_equal 302, browser_a.response.status
    secret_a = @user.reload.totp_secret

    browser_b.post identity_security_totp_setup_path
    assert_equal 302, browser_b.response.status
    secret_b = @user.reload.totp_secret
    refute_equal secret_a, secret_b

    browser_a.post identity_security_totp_confirm_path, params: {
      totp: { password: "password123", code: ROTP::TOTP.new(secret_a).now }
    }
    assert_equal 302, browser_a.response.status
    refute @user.reload.totp_enabled?
    assert_equal secret_b, @user.totp_secret

    browser_b.post identity_security_totp_confirm_path, params: {
      totp: { password: "password123", code: ROTP::TOTP.new(secret_b).now }
    }
    assert_equal 302, browser_b.response.status
    assert @user.reload.totp_enabled?
    assert_equal secret_b, @user.totp_secret
    assert_equal 1, AuditLog.where(
      action: "identity.totp_enabled",
      resource_id: @user.id
    ).count
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

  test "email change creates a pending request and waits for replacement confirmation" do
    other_session = create_test_session(@user).value.fetch(:session)

    assert_difference -> {
      Identity::EmailChangeRequest.where(user: @user, status: :pending).count
    }, 1 do
      assert_difference -> {
        Operations::DurableEnqueueIntent.where(
          handler_key: Identity::EmailChangeDelivery::HANDLER_KEY
        ).count
      }, 2 do
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
    refute_equal "changed@example.com", @user.reload.email
    assert @user.email_verified?
    refute other_session.reload.revoked?
    follow_redirect!
    assert_includes response.body, "changed@example.com"
  end

  test "confirmation switches the email and revokes every session except the initiating one" do
    current_session = @user.sessions.active.order(created_at: :desc).first
    other_session = create_test_session(@user).value.fetch(:session)
    request_result = Identity::ChangeEmail.call(
      user: @user,
      email: "confirmed@example.com",
      password: "password123",
      current_session:
    )
    request_record = request_result.value.fetch(:email_change_request)

    get identity_email_change_confirmation_path(token: request_record.confirmation_token)

    assert_redirected_to identity_security_path
    assert_equal "confirmed@example.com", @user.reload.email
    assert @user.email_verified?
    refute current_session.reload.revoked?
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

    assert_response :see_other
    assert_redirected_to signed_out_landing_path
    assert @user.reload.deleted?
    assert_not session[:session_token].present?
    assert AuditLog.exists?(action: "identity.account_closed", resource_id: @user.id)
    assert_equal "completed", @user.account_closure_results.dig("identity.profile", "status")
  end
end
