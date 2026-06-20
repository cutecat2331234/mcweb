# frozen_string_literal: true

module Identity
  class VerifyEmail < ApplicationService
    TOKEN_TTL = 24.hours

    def initialize(token:, ip_address: nil)
      @token = token.to_s
      @ip_address = ip_address
    end

    def call
      if @ip_address.present?
        rate_limit_result = Administration::RateLimiter.call(
          key: "verify_email:#{@ip_address}",
          limit: 30,
          window: 15.minutes
        )
        return ServiceResult.failure(error: "验证链接无效或已过期。") if rate_limit_result.failure?
      end

      user = User.find_by(email_verification_token_digest: digest_token(@token))
      return ServiceResult.failure(error: "验证链接无效或已过期。") unless user
      return ServiceResult.failure(error: "验证链接无效或已过期。") if token_expired?(user)
      return ServiceResult.success(user) if user.email_verified?

      user.update!(
        email_verified: true,
        email_verified_at: Time.current,
        email_verification_token_digest: nil,
        email_verification_sent_at: nil
      )

      Administration::AuditLogger.call(
        actor: user,
        action: "identity.verify_email",
        resource: user
      )

      ServiceResult.success(user)
    end

    private

    def digest_token(token)
      Digest::SHA256.hexdigest(token)
    end

    def token_expired?(user)
      user.email_verification_sent_at.blank? || user.email_verification_sent_at < TOKEN_TTL.ago
    end
  end
end
