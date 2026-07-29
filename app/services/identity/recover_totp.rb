# frozen_string_literal: true

module Identity
  class RecoverTotp < ApplicationService
    TOKEN_TTL = 30.minutes
    GENERIC_MESSAGE = "totp_recovery_email_sent"

    def initialize(email: nil, token: nil, password: nil, ip_address: nil, user_agent: nil)
      @email = email.to_s.strip.downcase.presence
      @token = token.to_s.presence
      @password = password.to_s
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return complete_recovery if @token.present?
      return request_recovery if @email.present?

      failure("email_or_token_required")
    end

    private

    def request_recovery
      limiter = Administration::RateLimiter.call(
        key: "totp_recovery_request:#{Digest::SHA256.hexdigest(@email)}:#{@ip_address}",
        limit: 5,
        window: 1.hour
      )
      return generic_success if limiter.failure?

      user = User.find_by("LOWER(email) = ?", @email)
      return generic_success unless user&.active? && user.email_verified? && user.totp_enabled?

      token = SecureRandom.urlsafe_base64(32)
      user.update!(
        totp_recovery_token_digest: digest_token(token),
        totp_recovery_sent_at: Time.current
      )

      Administration::AuditLogger.call(
        actor: user,
        action: "identity.totp_recovery_requested",
        resource: user,
        metadata: { delivery: "verified_email" },
        ip_address: @ip_address,
        user_agent: @user_agent
      )

      MailDeliveryJob.perform_later(
        "Identity::Mailer",
        "totp_recovery_email",
        "deliver_now",
        args: [ user.id, token ]
      )

      generic_success
    end

    def complete_recovery
      limiter = Administration::RateLimiter.call(
        key: "totp_recovery_complete:#{@ip_address}",
        limit: 20,
        window: 15.minutes
      )
      return limiter if limiter.failure?

      user = User.find_by(totp_recovery_token_digest: digest_token(@token))
      return failure("invalid_or_expired_totp_recovery_token") unless valid_token?(user)
      return failure("password_incorrect") unless user.authenticate(@password)

      User.transaction do
        user.lock!
        return failure("invalid_or_expired_totp_recovery_token") unless valid_token?(user)

        user.update!(
          totp_enabled: false,
          totp_secret: nil,
          recovery_codes: nil,
          totp_recovery_token_digest: nil,
          totp_recovery_sent_at: nil,
          failed_login_count: 0,
          locked_until: nil
        )
        Session.where(user: user, revoked_at: nil)
          .update_all(revoked_at: Time.current, updated_at: Time.current)

        Administration::AuditLogger.call(
          actor: user,
          action: "identity.totp_recovered",
          resource: user,
          metadata: { sessions_revoked: true, method: "verified_email_and_password" },
          before_state: { totp_enabled: true },
          after_state: { totp_enabled: false },
          ip_address: @ip_address,
          user_agent: @user_agent
        )
      end

      ServiceResult.success(user: user)
    end

    def valid_token?(user)
      user.present? &&
        user.active? &&
        user.totp_enabled? &&
        user.totp_recovery_sent_at.present? &&
        user.totp_recovery_sent_at >= TOKEN_TTL.ago
    end

    def generic_success
      ServiceResult.success(message: GENERIC_MESSAGE)
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end

    def digest_token(token)
      Digest::SHA256.hexdigest(token.to_s)
    end
  end
end
