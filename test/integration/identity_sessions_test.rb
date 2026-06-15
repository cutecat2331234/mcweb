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

    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
    assert session[:session_token].present? || cookies[:session_token].present?,
           "Expected auth token to be stored after login"
  end

  test "sign in with flat params is rejected" do
    post identity_session_path, params: {
      email: @user.email, password: "password123"
    }

    assert_includes [400, 404, 422, 500], response.status,
                    "Expected flat login params to fail, got #{response.status}"
  end

  test "sign in with wrong password re-renders form" do
    post identity_session_path, params: {
      session: { email: @user.email, password: "wrong-password" }
    }

    assert_response :unprocessable_entity
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
end
