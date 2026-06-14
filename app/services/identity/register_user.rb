# frozen_string_literal: true

module Identity
  class RegisterUser < ApplicationService
    def initialize(email:, username:, password:, display_name: nil, locale: "zh-CN", time_zone: "Asia/Shanghai")
      @email = email.to_s.strip.downcase
      @username = username.to_s.strip
      @password = password
      @display_name = display_name.presence || @username
      @locale = locale
      @time_zone = time_zone
    end

    def call
      verification_token = generate_token

      user = User.create!(
        public_id: generate_public_id,
        email: @email,
        username: @username,
        password: @password,
        display_name: @display_name,
        locale: @locale,
        time_zone: @time_zone,
        email_verified: false,
        email_verification_token_digest: digest_token(verification_token),
        email_verification_sent_at: Time.current
      )

      Administration::AuditLogger.call(
        actor: user,
        action: "identity.register",
        resource: user,
        metadata: { email: @email, username: @username }
      )

      ServiceResult.success(user: user, verification_token: verification_token)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def generate_public_id
      "usr_#{SecureRandom.alphanumeric(16)}"
    end

    def generate_token
      SecureRandom.urlsafe_base64(32)
    end

    def digest_token(token)
      Digest::SHA256.hexdigest(token)
    end
  end
end
