# frozen_string_literal: true

module Identity
  class EnableTotp < ApplicationService
    RATE_LIMIT = 10
    RATE_WINDOW = 15.minutes

    def initialize(
      user:,
      secret:,
      password:,
      code:,
      current_session:,
      ip_address: nil,
      user_agent: nil
    )
      @user = user
      @secret = secret.to_s
      @password = password.to_s
      @code = code.to_s
      @current_session = current_session
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return failure("totp_setup_missing") if @secret.blank?
      return failure("totp_current_session_required") unless valid_current_session?

      limiter = Administration::RateLimiter.call(
        key: "identity:totp_enable:#{@user.id}:#{@ip_address.presence || 'unknown'}",
        limit: RATE_LIMIT,
        window: RATE_WINDOW
      )
      return limiter if limiter.failure?

      enabled_at = Time.current
      recovery_codes = nil
      revoked_session_count = 0
      rotated_session_token = nil
      locked_session = nil
      replayed = false

      User.transaction do
        @user.lock!
        locked_session = Session.lock.find_by(id: @current_session.id, user_id: @user.id)
        unless locked_session&.active?
          raise VerificationFailed, failure("totp_current_session_required")
        end
        unless secure_secret_match?(@user.totp_secret.to_s, @secret)
          raise VerificationFailed, failure("totp_setup_stale")
        end

        verification = SensitiveActionVerifier.call(
          user: @user,
          password: @password,
          code: @code,
          consume_recovery_code: false
        )
        raise VerificationFailed, verification unless verification.success?
        unless User.verify_totp_code(@secret, @code)
          raise VerificationFailed, failure("invalid_two_factor_code")
        end

        if @user.totp_enabled?
          replayed = true
          recovery_codes = Array(@user.recovery_codes)
          next
        end

        @user.update!(totp_enabled: true)
        revoked_session_count = Session.active
          .where(user: @user)
          .where.not(id: locked_session.id)
          .update_all(revoked_at: enabled_at, updated_at: enabled_at)
        rotated_session_token = locked_session.rotate_token!
        recovery_codes = Array(@user.recovery_codes)

        audit_result = Administration::AuditLogger.call(
          actor: @user,
          action: "identity.totp_enabled",
          resource: @user,
          metadata: {
            verification_method: "password_and_totp",
            revoked_session_count: revoked_session_count
          },
          before_state: {
            totp_enabled: false,
            other_active_session_count: revoked_session_count
          },
          after_state: {
            totp_enabled: true,
            other_active_session_count: 0,
            current_session_token_rotated: true
          },
          ip_address: @ip_address,
          user_agent: @user_agent
        )
        raise AuditFailed unless audit_result.success?
      end

      unless replayed
        MailDeliveryJob.perform_later(
          "Identity::Mailer",
          "totp_enabled_email",
          "deliver_now",
          args: [ @user.id, enabled_at.iso8601, revoked_session_count ]
        )
      end

      ServiceResult.success(
        user: @user.reload,
        recovery_codes: recovery_codes,
        revoked_session_count: revoked_session_count,
        current_session: locked_session,
        session_token: rotated_session_token,
        replayed: replayed,
        enabled_at: enabled_at
      )
    rescue VerificationFailed => e
      e.result
    rescue AuditFailed
      failure("totp_enable_audit_failed")
    end

    class VerificationFailed < StandardError
      attr_reader :result

      def initialize(result)
        @result = result
        super(result.code)
      end
    end

    class AuditFailed < StandardError; end

    private

    def valid_current_session?
      @user&.persisted? &&
        @current_session&.persisted? &&
        @current_session.user_id == @user.id &&
        @current_session.active?
    end

    def secure_secret_match?(stored_secret, pending_secret)
      stored_secret.bytesize == pending_secret.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(stored_secret, pending_secret)
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
