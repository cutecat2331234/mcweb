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
      rate_limit_result = Administration::RateLimiter.call(
        key: "login:#{@email}:#{@ip_address}",
        limit: 10,
        window: 15.minutes
      )
      return ServiceResult.failure(error: "Too many login attempts. Please try again later.") if rate_limit_result.failure?

      user = User.find_by(email: @email)
      return generic_failure unless user

      return ServiceResult.failure(error: "Account is banned.") if banned?(user)
      return ServiceResult.failure(error: "Account is temporarily locked.") if locked?(user)

      unless user.authenticate(@password)
        record_failed_login(user)
        return generic_failure
      end

      if user.totp_enabled? || user.require_totp?
        return ServiceResult.failure(error: "Two-factor authentication code is required.") if @totp_code.blank?
        return ServiceResult.failure(error: "Invalid two-factor authentication code.") unless verify_totp(user)
      end

      user.update!(
        failed_login_count: 0,
        locked_until: nil,
        last_sign_in_at: Time.current,
        last_sign_in_ip: @ip_address
      )

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

    def banned?(user)
      return true if user.status == "banned"

      user.banned_at.present? && (user.ban_expires_at.nil? || user.ban_expires_at.future?)
    end

    def locked?(user)
      user.locked_until&.future?
    end

    def verify_totp(user)
      secret = user.totp_secret
      return false if secret.blank?

      ROTP::TOTP.new(secret).verify(@totp_code.to_s, drift_behind: 15, drift_ahead: 15)
    end

    def record_failed_login(user)
      failed_count = user.failed_login_count + 1
      attributes = { failed_login_count: failed_count }
      attributes[:locked_until] = LOCKOUT_DURATION.from_now if failed_count >= MAX_FAILED_ATTEMPTS
      user.update!(attributes)
    end

    def generic_failure
      ServiceResult.failure(error: "Invalid email or password.")
    end
  end
end
