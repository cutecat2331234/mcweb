# frozen_string_literal: true

require "test_helper"

class Administration::BanUserSessionTest < ActiveSupport::TestCase
  setup do
    @admin = create_user
    @target = create_user
    @session_result = Identity::SessionManager.call(
      user: @target,
      ip_address: "127.0.0.1",
      user_agent: "Test"
    )
    @session = @session_result.value[:session]
  end

  test "ban revokes active sessions" do
    result = Administration::BanUser.call(user: @target, actor: @admin, reason: "spam")
    assert result.success?
    assert @session.reload.revoked?
  end
end

class Identity::DeletedUserAuthTest < ActiveSupport::TestCase
  test "rejects login for deleted account" do
    user = create_user(email: "deleted@example.com", username: "deleteduser")
    user.soft_delete!

    result = Identity::AuthenticateUser.call(
      email: "deleted@example.com",
      password: "password123",
      ip_address: "127.0.0.1",
      user_agent: "Test"
    )

    assert result.failure?
    assert_match(/deleted/i, result.error)
  end
end

class Identity::VerifyEmailExpiryTest < ActiveSupport::TestCase
  test "rejects expired verification token" do
    token = SecureRandom.urlsafe_base64(32)
    User.create!(
      email: "expired@example.com",
      username: "expireduser",
      password: "password123",
      password_confirmation: "password123",
      email_verified: false,
      email_verification_token_digest: Digest::SHA256.hexdigest(token),
      email_verification_sent_at: 25.hours.ago
    )

    result = Identity::VerifyEmail.call(token: token)
    assert result.failure?
  end
end

class Payments::StripeProviderMissingSecretTest < ActiveSupport::TestCase
  test "rejects webhook when secret is not configured" do
    Payments::ProviderConfig.where(provider: "stripe").delete_all
    provider = Payments::StripeProvider.new

    refute provider.verify_webhook_signature(
      payload: "{}",
      signature: "t=1,v1=abc",
      headers: { "HTTP_STRIPE_SIGNATURE" => "t=1,v1=abc" }
    )
  end
end

class Payments::FakeProviderProductionSecretTest < ActiveSupport::TestCase
  test "rejects webhook when secret is not configured" do
    provider = Payments::FakeProvider.new
    provider.define_singleton_method(:webhook_secret) { nil }

    refute provider.verify_webhook_signature(payload: "{}", signature: "deadbeef")
  end
end

class UserSoftDeleteSessionTest < ActiveSupport::TestCase
  test "soft delete revokes active sessions" do
    user = create_user
    session_result = Identity::SessionManager.call(
      user: user,
      ip_address: "127.0.0.1",
      user_agent: "Test"
    )
    session = session_result.value[:session]

    user.soft_delete!
    assert session.reload.revoked?
  end
end

class BannedSessionIntegrationTest < ActionDispatch::IntegrationTest
  test "banned user loses access on next request" do
    user = create_user
    sign_in_as(user)

    get forum_notifications_path
    assert_response :success

    user.update!(status: :banned, banned_at: Time.current)

    get forum_notifications_path
    assert_redirected_to identity_sign_in_path
  end
end
