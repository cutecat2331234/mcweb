# frozen_string_literal: true

module Identity
  class ResendEmailVerification < ApplicationService
    RESEND_COOLDOWN = 2.minutes

    def initialize(email:, ip_address: nil)
      @email = email.to_s.strip.downcase
      @ip_address = ip_address
    end

    def call
      rate_limit_result = Administration::RateLimiter.call(
        key: "resend_verification:#{@email}:#{@ip_address}",
        limit: 5,
        window: 1.hour
      )
      return generic_success if rate_limit_result.failure?

      user = User.find_by(email: @email)
      return generic_success unless user

      User.transaction do
        user.lock!
        if user.email_verified? && !user.developer_mode_email_verified?
          raise ActiveRecord::Rollback
        end
        if user.email_verification_sent_at.present? &&
            user.email_verification_sent_at > RESEND_COOLDOWN.ago
          raise ActiveRecord::Rollback
        end

        token = user.generate_email_verification_token!
        Identity::EmailVerificationDelivery.record!(user:, token:)
      end

      generic_success
    rescue Operations::DurableEnqueue::InvalidRequest,
           Operations::DurableEnqueue::IdempotencyConflict => e
      Rails.logger.error("[identity.verification_resend] durable_delivery_unavailable error=#{e.class}")
      generic_success
    end

    private

    def generic_success
      ServiceResult.success
    end
  end
end
