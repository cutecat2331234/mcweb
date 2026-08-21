# frozen_string_literal: true

require "digest"

module Identity
  module EmailVerificationDelivery
    HANDLER_KEY = "identity.verification_email"

    module_function

    def record!(user:, token:)
      token_digest = Digest::SHA256.hexdigest(token.to_s)
      unless token.present? && user.email_verification_token_digest == token_digest
        raise Operations::DurableEnqueue::InvalidRequest,
              "email_verification_delivery_token_mismatch"
      end

      Operations::DurableEnqueue.record!(
        handler: HANDLER_KEY,
        source_id: user.id,
        dedupe_key: "email-verification:#{user.id}:#{token_digest}",
        arguments: { token_digest: }
      )
    end

    def deliver(intent)
      user = User.find_by(id: intent.source_id)
      return skipped("source_missing") unless user
      if user.email_verified? && !user.developer_mode_email_verified?
        return skipped("email_already_verified")
      end

      expected_digest = intent.arguments.fetch("token_digest")
      token = user.email_verification_token.to_s
      return skipped("verification_token_missing") if token.blank?
      return skipped("verification_token_expired") if verification_token_expired?(user)

      actual_digest = Digest::SHA256.hexdigest(token)
      unless secure_match?(actual_digest, expected_digest) &&
          secure_match?(user.email_verification_token_digest.to_s, expected_digest)
        return skipped("verification_token_superseded")
      end

      Identity::Mailer.verification_email(user.id, token).deliver_now
      Operations::DurableEnqueueResult.succeeded
    end

    def verification_token_expired?(user)
      user.email_verification_sent_at.blank? ||
        user.email_verification_sent_at < Identity::VerifyEmail::TOKEN_TTL.ago
    end
    private_class_method :verification_token_expired?

    def secure_match?(left, right)
      left.bytesize == right.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(left, right)
    end
    private_class_method :secure_match?

    def skipped(code)
      Operations::DurableEnqueueResult.skipped(error_code: code)
    end
    private_class_method :skipped
  end
end
