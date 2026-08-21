# frozen_string_literal: true

module Identity
  class ResetPassword < ApplicationService
    TOKEN_TTL = 1.hour

    class CompletionStepFailed < StandardError
      attr_reader :result

      def initialize(result)
        @result = result
        super(result.code.presence || "password_reset_completion_failed")
      end
    end

    def initialize(email: nil, token: nil, new_password: nil, ip_address: nil)
      @email = email&.to_s&.strip&.downcase
      @token = token
      @new_password = new_password
      @ip_address = ip_address
    end

    def call
      if @token.present? && @new_password.present?
        complete_reset
      elsif @email.present?
        request_reset
      else
        ServiceResult.failure(
          error: "email_or_token_required",
          code: "email_or_token_required"
        )
      end
    end

    private

    def request_reset
      rate_limit_result = Administration::RateLimiter.call(
        key: "password_reset:email:#{@email}:#{@ip_address}",
        limit: 5,
        window: 1.hour
      )
      if rate_limit_result.failure?
        return ServiceResult.success(
          message: I18n.t("mcweb.user_copy.password_reset_request_accepted")
        )
      end

      user = User.find_by(email: @email)
      unless user
        return ServiceResult.success(
          message: I18n.t("mcweb.user_copy.password_reset_request_accepted")
        )
      end

      reset_token = generate_token
      user.update!(
        password_reset_token_digest: digest_token(reset_token),
        password_reset_sent_at: Time.current
      )

      Administration::AuditLogger.call(
        actor: user,
        action: "identity.password_reset_requested",
        resource: user
      )

      MailDeliveryJob.perform_later(
        "Identity::Mailer",
        "password_reset_email",
        "deliver_now",
        args: [ user.id, reset_token ]
      )

      ServiceResult.success(user: user, reset_token: reset_token)
    end

    def complete_reset
      rate_limit_result = Administration::RateLimiter.call(
        key: "password_reset_complete:#{@ip_address}",
        limit: 20,
        window: 15.minutes
      )
      return rate_limit_result if rate_limit_result.failure?

      token_digest = digest_token(@token)
      candidate = User.find_by(password_reset_token_digest: token_digest)
      return invalid_reset_token unless candidate

      outcome = nil
      User.transaction do
        user = User.lock.find(candidate.id)
        unless secure_digest_match?(user.password_reset_token_digest, token_digest)
          outcome = invalid_reset_token
          raise ActiveRecord::Rollback
        end
        if token_expired?(user)
          outcome = expired_reset_token
          raise ActiveRecord::Rollback
        end

        user.update!(
          password: @new_password,
          password_reset_token_digest: nil,
          password_reset_sent_at: nil,
          failed_login_count: 0,
          locked_until: nil
        )

        # Keep credential mutation, token consumption, revocation and audit in
        # one transaction. Model-level revocation remains the extension point
        # for downstream session lifecycle behavior.
        Session.where(user:, revoked_at: nil).find_each(&:revoke!)

        audit_result = Administration::AuditLogger.call(
          actor: user,
          action: "identity.password_reset_completed",
          resource: user
        )
        raise CompletionStepFailed, audit_result if audit_result.failure?

        outcome = ServiceResult.success(user)
      end

      outcome
    rescue CompletionStepFailed => e
      e.result
    rescue ActiveRecord::RecordNotFound
      invalid_reset_token
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    def token_expired?(user)
      user.password_reset_sent_at.blank? || user.password_reset_sent_at < TOKEN_TTL.ago
    end

    def generate_token
      SecureRandom.urlsafe_base64(32)
    end

    def digest_token(token)
      Digest::SHA256.hexdigest(token)
    end

    def secure_digest_match?(stored_digest, expected_digest)
      stored = stored_digest.to_s
      stored.bytesize == expected_digest.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(stored, expected_digest)
    end

    def invalid_reset_token
      ServiceResult.failure(
        error: "invalid_or_expired_reset_token",
        code: "invalid_or_expired_reset_token"
      )
    end

    def expired_reset_token
      ServiceResult.failure(
        error: "reset_token_expired",
        code: "reset_token_expired"
      )
    end
  end
end
