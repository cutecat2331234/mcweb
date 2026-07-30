# frozen_string_literal: true

module Identity
  class ResetPassword < ApplicationService
    TOKEN_TTL = 1.hour

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

      user = User.find_by(password_reset_token_digest: digest_token(@token))
      unless user
        return ServiceResult.failure(
          error: "invalid_or_expired_reset_token",
          code: "invalid_or_expired_reset_token"
        )
      end
      if token_expired?(user)
        return ServiceResult.failure(
          error: "reset_token_expired",
          code: "reset_token_expired"
        )
      end

      user.update!(
        password: @new_password,
        password_reset_token_digest: nil,
        password_reset_sent_at: nil,
        failed_login_count: 0,
        locked_until: nil
      )

      # Use the model revocation path so edition extensions and security
      # callbacks (for example, disconnecting an active realtime session) run
      # for every credential invalidated by the password change.
      Session.where(user: user, revoked_at: nil).find_each(&:revoke!)

      Administration::AuditLogger.call(
        actor: user,
        action: "identity.password_reset_completed",
        resource: user
      )

      ServiceResult.success(user)
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
  end
end
