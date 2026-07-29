# frozen_string_literal: true

module Identity
  class AuthenticateUser < ApplicationService
    MAX_FAILED_ATTEMPTS = 5
    LOCKOUT_DURATION = 15.minutes

    def initialize(email:, password:, totp_code: nil, ip_address: nil, user_agent: nil, remember_me: false)
      @email = email.to_s.strip.downcase
      @password = password
      @totp_code = totp_code
      @ip_address = ip_address
      @user_agent = user_agent
      @remember_me = remember_me
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

      if user.totp_enabled? && !Mcweb::DeveloperMode.allow?(:skip_two_factor)
        if @totp_code.blank?
          return ServiceResult.failure(
            error: "two_factor_code_required",
            code: "two_factor_code_required"
          )
        end
        unless verify_second_factor(user)
          return ServiceResult.failure(
            error: "invalid_two_factor_code",
            code: "invalid_two_factor_code"
          )
        end
      end

      sign_in_attributes = {
        last_sign_in_at: Time.current,
        last_sign_in_ip: @ip_address
      }
      unless Mcweb::DeveloperMode.allow?(:skip_account_lockout)
        sign_in_attributes[:failed_login_count] = 0
        sign_in_attributes[:locked_until] = nil
      end
      user.update!(sign_in_attributes)

      session_result = SessionManager.call(
        user: user,
        ip_address: @ip_address,
        user_agent: @user_agent,
        remember_me: @remember_me
      )
      return session_result if session_result.failure?

      Administration::AuditLogger.call(
        actor: user,
        action: "identity.sign_in",
        resource: user,
        ip_address: @ip_address,
        user_agent: @user_agent
      )

      ServiceResult.success(session: session_result.value[:session], token: session_result.value[:token])
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

    def verify_second_factor(user)
      verify_totp(user) || user.consume_recovery_code!(@totp_code.to_s)
    end

    def verify_totp(user)
      User.verify_totp_code(user.totp_secret, @totp_code)
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
