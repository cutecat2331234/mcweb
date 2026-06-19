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
      return ServiceResult.failure(error: "登录尝试过于频繁，请稍后再试。") if rate_limit_result.failure?

      user = User.find_by(email: @email)
      return generic_failure unless user

      clear_expired_ban!(user)
      return ServiceResult.failure(error: "该账户已被封禁。") if user.banned?
      return ServiceResult.failure(error: "该账户已被删除。") if user.deleted?
      return ServiceResult.failure(error: "账户已临时锁定，请稍后再试。") if locked?(user)

      unless user.authenticate(@password)
        record_failed_login(user)
        return generic_failure
      end

      unless user.email_verified?
        return ServiceResult.failure(error: "请先验证邮箱后再登录。")
      end

      if user.totp_enabled? || user.require_totp?
        return ServiceResult.failure(error: "请输入两步验证码。") if @totp_code.blank?
        return ServiceResult.failure(error: "两步验证码无效。") unless verify_totp(user)
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

    def clear_expired_ban!(user)
      return unless user.status == "banned"
      return if user.ban_expires_at.nil? || user.ban_expires_at.future?

      user.unban!
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
      ServiceResult.failure(error: "邮箱或密码错误。")
    end
  end
end
