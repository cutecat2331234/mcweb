# frozen_string_literal: true

require "test_helper"

class DeveloperModeIdentityTest < ActiveSupport::TestCase
  test "unrestricted mode bypasses rate limits without writing counters" do
    key = "developer-mode:#{SecureRandom.hex(8)}"

    with_unrestricted_developer_mode do
      assert_no_difference -> { RateLimitCounter.where(key: key).count } do
        3.times do
          result = Administration::RateLimiter.call(
            key: key,
            limit: 1,
            window: 1.hour
          )

          assert result.success?
          assert result.value[:developer_mode_bypassed]
          assert_nil result.value[:remaining]
        end
      end
    end
  end

  test "registration accepts a short password auto verifies and skips verification mail" do
    suffix = SecureRandom.hex(6)
    Administration::EmailBan.create!(pattern: "*@developer-mode.test")
    result = nil

    with_unrestricted_developer_mode do
      assert_no_enqueued_jobs only: MailDeliveryJob do
        result = Identity::RegisterUser.call(
          email: "member-#{suffix}@developer-mode.test",
          username: "dev#{suffix}",
          password: "x",
          ip_address: "203.0.113.15"
        )
      end
    end

    assert result.success?
    user = result.value[:user]
    assert user.email_verified?
    assert user.email_verified_at.present?
    assert user.developer_mode_email_verified?
    assert user.developer_mode_relaxed_password?
    assert_nil user.email_verification_token_digest
    assert_nil user.email_verification_sent_at
    assert_nil result.value[:verification_token]
  end

  test "developer mode credentials require production verification and password remediation" do
    suffix = SecureRandom.hex(6)
    registration = nil

    with_unrestricted_developer_mode do
      registration = Identity::RegisterUser.call(
        email: "remediate-#{suffix}@example.com",
        username: "fix#{suffix}",
        password: "x",
        ip_address: "203.0.113.18"
      )
    end

    assert registration.success?
    user = registration.value[:user]

    blocked = Identity::AuthenticateUser.call(
      email: user.email,
      password: "x",
      ip_address: "203.0.113.19",
      user_agent: "DeveloperModeIdentityTest"
    )
    assert blocked.failure?

    user = User.find(user.id)
    verification_token = user.generate_email_verification_token!
    verification = Identity::VerifyEmail.call(
      token: verification_token,
      ip_address: "203.0.113.20"
    )
    assert verification.success?
    assert_not user.reload.developer_mode_email_verified?

    password_token = user.generate_password_reset_token!
    reset = Identity::ResetPassword.call(
      token: password_token,
      new_password: "password123",
      ip_address: "203.0.113.21"
    )
    assert reset.success?
    assert_not user.reload.developer_mode_relaxed_password?

    authenticated = Identity::AuthenticateUser.call(
      email: user.email,
      password: "password123",
      ip_address: "203.0.113.22",
      user_agent: "DeveloperModeIdentityTest"
    )
    assert authenticated.success?
  end

  test "developer mode auto verified accounts can request production verification" do
    suffix = SecureRandom.hex(6)
    registration = nil

    with_unrestricted_developer_mode do
      registration = Identity::RegisterUser.call(
        email: "verify-#{suffix}@example.com",
        username: "verify#{suffix}",
        password: "password123",
        ip_address: "203.0.113.23"
      )
    end

    user = registration.value[:user]
    assert user.developer_mode_email_verified?

    assert_enqueued_jobs 1 do
      result = Identity::ResendEmailVerification.call(
        email: user.email,
        ip_address: "203.0.113.24"
      )
      assert result.success?
    end

    assert user.reload.email_verification_token_digest.present?
    assert user.email_verification_sent_at.present?
  end

  test "authentication bypasses verification totp and lockout without destroying their state" do
    user = create_user(
      email: "locked-#{SecureRandom.hex(6)}@example.com",
      username: "locked#{SecureRandom.hex(5)}",
      email_verified: false,
      email_verified_at: nil,
      failed_login_count: 5,
      locked_until: 1.hour.from_now
    )
    user.setup_totp!
    user.update!(totp_enabled: true)
    original_locked_until = user.locked_until
    original_recovery_codes = user.recovery_codes

    with_unrestricted_developer_mode do
      result = Identity::AuthenticateUser.call(
        email: user.email,
        password: "password123",
        ip_address: "203.0.113.16",
        user_agent: "DeveloperModeIdentityTest"
      )

      assert result.success?
    end

    user.reload
    assert_not user.email_verified?
    assert user.totp_enabled?
    assert_equal original_recovery_codes, user.recovery_codes
    assert_equal 5, user.failed_login_count
    assert_equal original_locked_until.to_i, user.locked_until.to_i
  end

  test "failed passwords do not mutate lockout counters while bypass is active" do
    user = create_user(
      failed_login_count: 4,
      locked_until: 30.minutes.from_now
    )
    original_locked_until = user.locked_until

    with_unrestricted_developer_mode do
      result = Identity::AuthenticateUser.call(
        email: user.email,
        password: "wrong-password",
        ip_address: "203.0.113.17",
        user_agent: "DeveloperModeIdentityTest"
      )

      assert result.failure?
    end

    user.reload
    assert_equal 4, user.failed_login_count
    assert_equal original_locked_until.to_i, user.locked_until.to_i
  end

  private

  def with_unrestricted_developer_mode(&block)
    settings = Mcweb::DeveloperMode.parse(
      config: {
        developer_mode: {
          enabled: true,
          preset: "unrestricted"
        }
      },
      environment: {}
    )

    previous_settings = Mcweb::DeveloperMode.instance_variable_get(:@settings)
    Mcweb::DeveloperMode.instance_variable_set(:@settings, settings)
    block.call
  ensure
    Mcweb::DeveloperMode.instance_variable_set(:@settings, previous_settings)
  end
end
