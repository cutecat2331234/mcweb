# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class IdentityPasswordSelfServiceTest < ActionDispatch::IntegrationTest
  include InertiaRails::Minitest

  test "password page requires a signed-in user" do
    get identity_security_password_path

    assert_redirected_to identity_sign_in_path
  end

  test "password page is a private no-store form" do
    user = create_user
    sign_in_as(user)

    get identity_security_password_path

    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "Identity/Passwords/Edit", inertia.component
    assert_equal false, inertia.props.deep_symbolize_keys.fetch(:totp_enabled)
  end

  test "signed-in password change keeps this session and revokes another device" do
    user = create_user
    sign_in_as(user)
    current_session = user.sessions.active.order(:created_at, :id).last
    other_session = Identity::SessionManager.call(user: user).value.fetch(:session)

    assert_enqueued_jobs 1, only: MailDeliveryJob do
      patch identity_security_password_path, params: {
        password_change: {
          current_password: "password123",
          new_password: "replacement456",
          new_password_confirmation: "replacement456",
          code: ""
        }
      }
    end

    assert_redirected_to identity_security_password_path
    user.reload
    assert user.authenticate("replacement456")
    refute user.authenticate("password123")
    refute current_session.reload.revoked?
    assert other_session.reload.revoked?

    follow_redirect!
    assert_response :success
    assert_equal "Identity/Passwords/Edit", inertia.component
  end

  test "invalid reauthentication returns only safe field errors" do
    user = create_user
    sign_in_as(user)

    patch identity_security_password_path, params: {
      password_change: {
        current_password: "wrong-password",
        new_password: "replacement456",
        new_password_confirmation: "replacement456",
        code: "123456"
      }
    }

    assert_response :unprocessable_entity
    assert_equal "private, no-store", response.headers["Cache-Control"]
    errors = inertia.props.deep_symbolize_keys.fetch(:form_errors)
    assert errors.key?(:"password_change.current_password")
    serialized = inertia.props.to_json
    refute_includes serialized, "wrong-password"
    refute_includes serialized, "replacement456"
    refute_includes serialized, "123456"
    assert user.reload.authenticate("password123")
  end

  test "rate limits repeated password change attempts" do
    user = create_user
    sign_in_as(user)
    limited = ServiceResult.failure(
      error: "rate_limited",
      code: "rate_limited",
      retry_after: 45
    )

    Administration::RateLimiter.stub(:call, limited) do
      patch identity_security_password_path, params: {
        password_change: {
          current_password: "password123",
          new_password: "replacement456",
          new_password_confirmation: "replacement456",
          code: ""
        }
      }
    end

    assert_response :too_many_requests
    assert_equal "45", response.headers["Retry-After"]
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end
end
