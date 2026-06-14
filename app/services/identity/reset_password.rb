# frozen_string_literal: true

module Identity
  class ResetPassword < ApplicationService
    TOKEN_TTL = 1.hour

    def initialize(email: nil, token: nil, new_password: nil)
      @email = email&.to_s&.strip&.downcase
      @token = token
      @new_password = new_password
    end

    def call
      if @token.present? && @new_password.present?
        complete_reset
      elsif @email.present?
        request_reset
      else
        ServiceResult.failure(error: "Email or token with new password is required.")
      end
    end

    private

    def request_reset
      user = User.find_by(email: @email)
      return ServiceResult.success(message: "If the email exists, a reset link has been sent.") unless user

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

      ServiceResult.success(user: user, reset_token: reset_token)
    end

    def complete_reset
      user = User.find_by(password_reset_token_digest: digest_token(@token))
      return ServiceResult.failure(error: "Invalid or expired reset token.") unless user
      return ServiceResult.failure(error: "Reset token has expired.") if token_expired?(user)

      user.update!(
        password: @new_password,
        password_reset_token_digest: nil,
        password_reset_sent_at: nil,
        failed_login_count: 0,
        locked_until: nil
      )

      Session.where(user: user).update_all(revoked_at: Time.current)

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
