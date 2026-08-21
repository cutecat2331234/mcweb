# frozen_string_literal: true

require "test_helper"

class IdentitySessionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(email: "login-test@example.com", username: "logintest")
  end

  test "sign in with nested session params redirects and sets session" do
    post identity_session_path, params: {
      session: { email: @user.email, password: "password123", remember_me: "0" }
    }

    assert_redirected_to forum_sections_path
    follow_redirect!
    assert_response :success
    assert session[:session_token].present? || cookies[:session_token].present?,
           "Expected auth token to be stored after login"
  end

  test "sign in with flat params is rejected" do
    post identity_session_path, params: {
      email: @user.email, password: "password123"
    }

    assert_includes [ 400, 404, 422, 500 ], response.status,
                    "Expected flat login params to fail, got #{response.status}"
  end

  test "sign in with wrong password re-renders form" do
    post identity_session_path, params: {
      session: { email: @user.email, password: "wrong-password" }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "login_error"
    assert_includes response.body, "邮箱或密码错误"
  end

  test "totp account moves to a separate verification page before creating a session" do
    @user.setup_totp!
    @user.update!(totp_enabled: true)

    assert_no_difference -> { @user.sessions.count } do
      post identity_session_path, params: {
        session: { email: @user.email, password: "password123", remember_me: "0" }
      }
    end

    assert_response :see_other
    assert_redirected_to identity_session_two_factor_path
    assert_not session[Authentication::SESSION_COOKIE].present?
    assert_not cookies[Authentication::SESSION_COOKIE].present?

    follow_redirect!
    assert_response :success
    assert_includes response.body, "Identity/Sessions/TwoFactor"
  end

  test "valid totp completes the pending login and preserves return destination" do
    @user.setup_totp!
    @user.update!(totp_enabled: true)
    get admin_root_path
    assert_redirected_to identity_sign_in_path
    assert_equal "/admin", session[:return_to]

    post identity_session_path, params: {
      session: { email: @user.email, password: "password123", remember_me: "1" }
    }
    assert_redirected_to identity_session_two_factor_path

    post identity_session_two_factor_path, params: {
      two_factor: { code: ROTP::TOTP.new(@user.totp_secret).now }
    }

    assert_redirected_to "/admin"
    assert session[Authentication::SESSION_COOKIE].present? ||
      cookies[Authentication::SESSION_COOKIE].present?
    assert @user.sessions.order(created_at: :desc).first.remember_me?
  end

  test "invalid totp stays on the separate verification page" do
    @user.setup_totp!
    @user.update!(totp_enabled: true)

    post identity_session_path, params: {
      session: { email: @user.email, password: "password123" }
    }
    post identity_session_two_factor_path, params: {
      two_factor: { code: "000000" }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "Identity/Sessions/TwoFactor"
    assert_includes response.body, I18n.t("mcweb.services.errors.invalid_two_factor_code")
    assert_not session[Authentication::SESSION_COOKIE].present?
    assert_not cookies[Authentication::SESSION_COOKIE].present?
  end

  test "recovery code completes the pending login and is consumed once" do
    @user.setup_totp!
    @user.update!(totp_enabled: true)
    recovery_code = @user.recovery_codes.first

    post identity_session_path, params: {
      session: { email: @user.email, password: "password123" }
    }
    post identity_session_two_factor_path, params: {
      two_factor: { code: recovery_code }
    }

    assert_redirected_to FeatureFlags.primary_portal_path(self)
    assert_equal 9, @user.reload.recovery_codes.size
    assert_not_includes @user.recovery_codes, recovery_code
  end

  test "expired or missing second-factor challenge returns to password login" do
    @user.setup_totp!
    @user.update!(totp_enabled: true)

    get identity_session_two_factor_path
    assert_response :see_other
    assert_redirected_to identity_sign_in_path

    post identity_session_path, params: {
      session: { email: @user.email, password: "password123" }
    }
    assert_redirected_to identity_session_two_factor_path

    travel 6.minutes do
      post identity_session_two_factor_path, params: {
        two_factor: { code: ROTP::TOTP.new(@user.totp_secret).now }
      }
    end

    assert_response :see_other
    assert_redirected_to identity_sign_in_path
    assert_equal I18n.t("mcweb.flash.two_factor_challenge_expired"), flash[:alert]
    assert_not session[Authentication::SESSION_COOKIE].present?
  end

  test "password replacement expires the opaque pending second-factor credential snapshot" do
    @user.setup_totp!
    @user.update!(totp_enabled: true)

    post identity_session_path, params: {
      session: { email: @user.email, password: "password123" }
    }
    assert_redirected_to identity_session_two_factor_path

    pending = session[:identity_pending_second_factor]
    credential_snapshot = pending.fetch("credential_snapshot")
    assert credential_snapshot.present?
    refute pending.key?("password_digest")
    refute_includes pending.values, @user.password_digest

    get identity_session_two_factor_path
    assert_response :success
    refute_includes response.body, credential_snapshot

    @user.update!(
      password: "replacement456",
      password_confirmation: "replacement456"
    )
    post identity_session_two_factor_path, params: {
      two_factor: { code: ROTP::TOTP.new(@user.totp_secret).now }
    }

    assert_response :see_other
    assert_redirected_to identity_sign_in_path
    assert_nil session[:identity_pending_second_factor]
    assert_not session[Authentication::SESSION_COOKIE].present?
  end

  test "wrong password does not reveal totp state or create a pending challenge" do
    @user.setup_totp!
    @user.update!(totp_enabled: true)

    post identity_session_path, params: {
      session: { email: @user.email, password: "wrong-password" }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "Identity/Sessions/New"
    assert_not_includes response.body, "Identity/Sessions/TwoFactor"
    assert_nil session[:identity_pending_second_factor]
  end

  test "sign in without csrf token is rejected when forgery protection enabled" do
    @old_forgery = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    begin
      post identity_session_path,
           params: { session: { email: @user.email, password: "password123" } },
           headers: { "X-CSRF-Token" => "invalid" }

      assert_response :unprocessable_entity
      assert_match(/rejected|Invalid|authenticity/i, response.body)
    ensure
      ActionController::Base.allow_forgery_protection = @old_forgery
    end
  end

  test "sign in ignores unsafe return_to destinations" do
    get identity_sign_in_path
    session[:return_to] = "//evil.com"

    post identity_session_path, params: { session: { email: @user.email, password: "password123" } }

    assert_redirected_to forum_sections_path
  end

  test "inertia sign in performs a full page visit when returning to admin" do
    get admin_root_path
    assert_redirected_to identity_sign_in_path
    assert_equal "/admin", session[:return_to]

    post identity_session_path,
         params: { session: { email: @user.email, password: "password123" } },
         headers: { "X-Inertia" => "true" }

    assert_response :conflict
    assert_equal "/admin", response.headers["X-Inertia-Location"]
    assert_equal I18n.t("mcweb.flash.sign_in_success"), flash[:notice]
  end

  test "get session redirects to sign in" do
    get identity_session_path
    assert_redirected_to identity_sign_in_path
  end

  test "legacy identity session path redirects to sign in" do
    get "/identity/session"
    assert_redirected_to identity_sign_in_path
  end

  test "destroy session signs user out" do
    post identity_session_path, params: {
      session: { email: @user.email, password: "password123", remember_me: "0" }
    }
    assert session[:session_token].present? || cookies[:session_token].present?

    delete identity_session_path
    assert_redirected_to root_path
    assert_not session[:session_token].present?
    assert_not cookies[:session_token].present?
  end

  test "revoking current session from management signs user out" do
    post identity_session_path, params: {
      session: { email: @user.email, password: "password123", remember_me: "0" }
    }
    follow_redirect!
    session_record = @user.sessions.active.order(last_active_at: :desc).first

    delete identity_sessions_management_path(session_record)

    assert_redirected_to identity_sign_in_path
    assert_not session[:session_token].present?
    assert_not cookies[:session_token].present?
    assert session_record.reload.revoked?
  end

  test "registration does not auto sign in before email verification" do
    suffix = SecureRandom.hex(4)
    post identity_registrations_path, params: {
      registration: {
        email: "regflow-#{suffix}@example.com",
        username: "regflow#{suffix}",
        password: "password123",
        display_name: "Reg Flow"
      }
    }

    assert_redirected_to identity_sign_in_path
    assert_not session[:session_token].present?
    assert_not cookies[:session_token].present?
  end
end
