# frozen_string_literal: true

module Identity
  class VerifyCredentials < ApplicationService
    MAX_FAILED_ATTEMPTS = 5
    LOCKOUT_DURATION = 15.minutes

    def initialize(email:, password:, ip_address: nil)
      @email = email.to_s.strip.downcase
      @password = password
      @ip_address = ip_address
    end

    def call
      rate_limit_result = Administration::AbuseRateLimit.call(
        action: :login,
        account: @email,
        ip_address: @ip_address
      )
      return rate_limit_result if rate_limit_result.failure?

      user = User.find_by(email: @email)
      return generic_failure unless user

      clear_expired_ban!(user)
      return generic_failure if user.banned?
      return generic_failure if user.deleted?
      return generic_failure unless user.session_eligible?
      if !Mcweb::DeveloperMode.allow?(:skip_account_lockout) && locked?(user)
        return generic_failure
      end

      unless user.authenticate(@password)
        record_failed_login(user) unless Mcweb::DeveloperMode.allow?(:skip_account_lockout)
        return generic_failure
      end

      if user.developer_mode_relaxed_password? && !Mcweb::DeveloperMode.allow?(:relax_password_policy)
        return generic_failure
      end

      unless production_email_verified?(user) || Mcweb::DeveloperMode.allow?(:skip_email_verification)
        return generic_failure
      end

      ServiceResult.success(
        user: user,
        two_factor_required: user.totp_enabled? && !Mcweb::DeveloperMode.allow?(:skip_two_factor)
      )
    end

    private

    def clear_expired_ban!(user)
      return unless user.status == "banned"
      return if user.ban_expires_at.nil? || user.ban_expires_at.future?

      user.unban!
    end

    def locked?(user)
      user.locked_until&.future?
    end

    def production_email_verified?(user)
      user.email_verified? && !user.developer_mode_email_verified?
    end

    def record_failed_login(user)
      failed_count = user.failed_login_count + 1
      attributes = { failed_login_count: failed_count }
      attributes[:locked_until] = LOCKOUT_DURATION.from_now if failed_count >= MAX_FAILED_ATTEMPTS
      user.update!(attributes)
    end

    def generic_failure
      ServiceResult.failure(
        error: "invalid_email_or_password",
        code: "invalid_email_or_password"
      )
    end
  end
end
