# frozen_string_literal: true

require "test_helper"

class IdentityErrorI18nTest < ActiveSupport::TestCase
  test "authentication failures expose stable codes and localized messages" do
    user = create_user
    user.setup_totp!
    user.update!(totp_enabled: true)

    each_locale do |locale|
      invalid_credentials = Identity::AuthenticateUser.call(
        email: "missing-#{locale}@example.com",
        password: "incorrect"
      )
      assert_localized_failure(invalid_credentials, "invalid_email_or_password", locale)

      missing_code = Identity::AuthenticateUser.call(
        email: user.email,
        password: "password123"
      )
      assert_localized_failure(missing_code, "two_factor_code_required", locale)

      invalid_code = Identity::AuthenticateUser.call(
        email: user.email,
        password: "password123",
        totp_code: "000000"
      )
      assert_localized_failure(invalid_code, "invalid_two_factor_code", locale)
    end
  end

  test "verification and password reset failures are localized by stable code" do
    each_locale do |locale|
      verification = Identity::VerifyEmail.call(
        token: "missing-#{locale}",
        ip_address: "192.0.2.#{locale == :en ? 10 : 11}"
      )
      assert_localized_failure(
        verification,
        "invalid_or_expired_verification_token",
        locale
      )

      missing_reset_input = Identity::ResetPassword.call
      assert_localized_failure(
        missing_reset_input,
        "email_or_token_required",
        locale
      )

      invalid_reset = Identity::ResetPassword.call(
        token: "missing-#{locale}",
        new_password: "password456",
        ip_address: "192.0.2.#{locale == :en ? 20 : 21}"
      )
      assert_localized_failure(
        invalid_reset,
        "invalid_or_expired_reset_token",
        locale
      )
    end
  end

  test "expired reset tokens retain their distinct stable code" do
    token = SecureRandom.urlsafe_base64(32)
    user = create_user
    user.update!(
      password_reset_token_digest: Digest::SHA256.hexdigest(token),
      password_reset_sent_at: 2.hours.ago
    )

    I18n.with_locale(:en) do
      result = Identity::ResetPassword.call(
        token: token,
        new_password: "password456",
        ip_address: "192.0.2.30"
      )

      assert_localized_failure(result, "reset_token_expired", :en)
    end
  end

  test "account access and email bans expose localized stable failures" do
    Administration::EmailBan.create!(pattern: "*@blocked-i18n.test")

    each_locale do |locale|
      account_access = Identity::AccountAccess.call(user: nil)
      assert_localized_failure(account_access, "authentication_required", locale)

      email_ban = Administration::CheckEmailBan.call(
        email: "user@blocked-i18n.test"
      )
      assert_localized_failure(email_ban, "email_banned_registration", locale)
    end
  end

  private

  def each_locale
    %i[en zh-CN].each do |locale|
      I18n.with_locale(locale) { yield locale }
    end
  end

  def assert_localized_failure(result, code, locale)
    assert_predicate result, :failure?
    assert_equal code, result.code
    assert_equal I18n.t("mcweb.services.errors.#{code}", locale: locale), result.error
  end
end
