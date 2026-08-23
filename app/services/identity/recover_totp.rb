# frozen_string_literal: true

module Identity
  class RecoverTotp < ApplicationService
    TOKEN_TTL = SecurityRecoveryMailDelivery::TOTP_RECOVERY_TTL
    GENERIC_MESSAGE = "totp_recovery_email_sent"

    class CompletionStepFailed < StandardError
      attr_reader :result

      def initialize(result)
        @result = result
        super(result.code.presence || "totp_recovery_completion_failed")
      end
    end

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

      SecurityRecoveryMailDelivery.issue!(
        user:,
        purpose: SecurityRecoveryMailDelivery::TOTP_RECOVERY,
        ip_address: @ip_address,
        user_agent: @user_agent
      )

      generic_success
    rescue SecurityRecoveryMailDelivery::AuditFailed,
           Operations::DurableEnqueue::InvalidRequest,
           Operations::DurableEnqueue::IdempotencyConflict,
           ActiveRecord::RecordInvalid,
           ActiveRecord::RecordNotFound => error
      Rails.logger.error("[identity.totp_recovery] durable_delivery_unavailable error=#{error.class}")
      generic_success
    end

    def complete_recovery
      limiter = Administration::RateLimiter.call(
        key: "totp_recovery_complete:#{@ip_address}",
        limit: 20,
        window: 15.minutes
      )
      return limiter if limiter.failure?

      token_digest = digest_token(@token)
      candidate = User.find_by(totp_recovery_token_digest: token_digest)
      return failure("invalid_or_expired_totp_recovery_token") unless candidate

      outcome = nil
      User.transaction do
        user = User.lock.find(candidate.id)
        unless valid_token?(user, token_digest)
          outcome = failure("invalid_or_expired_totp_recovery_token")
          raise ActiveRecord::Rollback
        end
        unless user.authenticate(@password)
          outcome = failure("password_incorrect")
          raise ActiveRecord::Rollback
        end

        user.update!(SecurityRecoveryMailDelivery.clear_attributes(
          SecurityRecoveryMailDelivery::TOTP_RECOVERY
        ).merge(
          totp_enabled: false,
          totp_secret: nil,
          recovery_codes: nil,
          failed_login_count: 0,
          locked_until: nil
        ))
        Session.where(user: user, revoked_at: nil)
          .update_all(revoked_at: Time.current, updated_at: Time.current)

        audit_result = Administration::AuditLogger.call(
          actor: user,
          action: "identity.totp_recovered",
          resource: user,
          metadata: { sessions_revoked: true, method: "verified_email_and_password" },
          before_state: { totp_enabled: true },
          after_state: { totp_enabled: false },
          ip_address: @ip_address,
          user_agent: @user_agent
        )
        raise CompletionStepFailed, audit_result if audit_result.failure?

        outcome = ServiceResult.success(user: user)
      end

      outcome
    rescue CompletionStepFailed => error
      error.result
    rescue ActiveRecord::RecordNotFound
      failure("invalid_or_expired_totp_recovery_token")
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end

    def valid_token?(user, expected_digest)
      stored_digest = user&.totp_recovery_token_digest.to_s
      user.present? &&
        user.active? &&
        user.email_verified? &&
        user.totp_enabled? &&
        user.totp_recovery_sent_at.present? &&
        user.totp_recovery_sent_at >= TOKEN_TTL.ago &&
        secure_match?(stored_digest, expected_digest)
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

    def secure_match?(left, right)
      left.bytesize == right.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(left, right)
    end
  end
end
