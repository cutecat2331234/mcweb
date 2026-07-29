# frozen_string_literal: true

module Identity
  class ChangeEmail < ApplicationService
    def initialize(user:, email:, password:, code: nil, current_session: nil, ip_address: nil, user_agent: nil)
      @user = user
      @email = email.to_s.strip.downcase
      @password = password
      @code = code
      @current_session = current_session
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return failure("email_required") if @email.blank?
      return failure("email_unchanged") if @email.casecmp?(@user.email)

      email_ban = Administration::CheckEmailBan.call(email: @email)
      return failure("email_not_available") if email_ban.failure?
      return failure("email_not_available") if User.where.not(id: @user.id).where("LOWER(email) = ?", @email).exists?

      token = SecureRandom.urlsafe_base64(32)
      auto_verify = Mcweb::DeveloperMode.allow?(:skip_email_verification)

      User.transaction do
        @user.lock!
        verification = SensitiveActionVerifier.call(
          user: @user,
          password: @password,
          code: @code
        )
        raise VerificationFailed, verification unless verification.success?

        before_domain = email_domain(@user.email)
        was_verified = @user.email_verified?
        @user.update!(
          email: @email,
          email_verified: auto_verify,
          email_verified_at: auto_verify ? Time.current : nil,
          developer_mode_email_verified: auto_verify,
          email_verification_token_digest: auto_verify ? nil : digest_token(token),
          email_verification_sent_at: auto_verify ? nil : Time.current
        )

        Session.where(user: @user, revoked_at: nil)
          .where.not(id: @current_session&.id)
          .update_all(revoked_at: Time.current, updated_at: Time.current)

        Administration::AuditLogger.call(
          actor: @user,
          action: "identity.email_changed",
          resource: @user,
          metadata: {
            verification_method: verification.value.fetch(:method),
            previous_domain: before_domain,
            replacement_domain: email_domain(@email),
            other_sessions_revoked: true
          },
          before_state: { email_verified: was_verified },
          after_state: { email_verified: auto_verify },
          ip_address: @ip_address,
          user_agent: @user_agent
        )
      end

      unless auto_verify
        MailDeliveryJob.perform_later(
          "Identity::Mailer",
          "verification_email",
          "deliver_now",
          args: [ @user.id, token ]
        )
      end

      ServiceResult.success(user: @user, verification_required: !auto_verify)
    rescue VerificationFailed => e
      e.result
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    class VerificationFailed < StandardError
      attr_reader :result

      def initialize(result)
        @result = result
        super(result.code)
      end
    end

    private

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end

    def digest_token(token)
      Digest::SHA256.hexdigest(token)
    end

    def email_domain(email)
      email.to_s.split("@", 2).last.to_s.downcase
    end
  end
end
