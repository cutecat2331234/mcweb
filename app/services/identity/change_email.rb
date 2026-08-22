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
      return failure("email_not_available") unless @email.match?(URI::MailTo::EMAIL_REGEXP)

      email_ban = Administration::CheckEmailBan.call(email: @email)
      return failure("email_not_available") if email_ban.failure?

      request = nil
      confirmation_token = SecureRandom.urlsafe_base64(32)
      revocation_token = SecureRandom.urlsafe_base64(32)
      requested_at = Time.current

      User.transaction do
        EmailAddressLock.acquire!(@user.email, @email)
        @user.lock!
        raise EmailUnavailable if @email.casecmp?(@user.email)
        expire_stale_target_requests!
        raise EmailUnavailable if email_unavailable?

        verification = SensitiveActionVerifier.call(
          user: @user,
          password: @password,
          code: @code
        )
        raise VerificationFailed, verification unless verification.success?

        before_domain = email_domain(@user.email)
        supersede_pending_requests!
        request = EmailChangeRequest.create!(
          user: @user,
          initiating_session: safe_initiating_session,
          original_email: @user.email,
          requested_email: @email,
          original_email_verified: @user.email_verified?,
          original_email_verified_at: @user.email_verified_at,
          confirmation_token: confirmation_token,
          confirmation_token_digest: digest_token(confirmation_token),
          revocation_token: revocation_token,
          revocation_token_digest: digest_token(revocation_token),
          requested_at:,
          expires_at: requested_at + EmailChangeRequest::CONFIRMATION_TTL
        )

        Administration::AuditLogger.call(
          actor: @user,
          action: "identity.email_change_requested",
          resource: request,
          metadata: {
            verification_method: verification.value.fetch(:method),
            previous_domain: before_domain,
            replacement_domain: email_domain(@email),
            confirmation_ttl_seconds: EmailChangeRequest::CONFIRMATION_TTL.to_i
          },
          before_state: { status: "none" },
          after_state: { status: "pending" },
          ip_address: @ip_address,
          user_agent: @user_agent
        )

        EmailChangeDelivery.record!(
          request:,
          confirmation_token:,
          revocation_token:
        )
      end

      ServiceResult.success(
        user: @user,
        email_change_request: request,
        pending_email: request.requested_email,
        verification_required: true
      )
    rescue VerificationFailed => e
      e.result
    rescue EmailUnavailable, ActiveRecord::RecordNotUnique
      failure("email_not_available")
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    rescue Operations::DurableEnqueue::InvalidRequest,
           Operations::DurableEnqueue::IdempotencyConflict => e
      Rails.logger.error("[identity.email_change] durable_delivery_unavailable error=#{e.class}")
      failure("email_delivery_temporarily_unavailable")
    end

    class VerificationFailed < StandardError
      attr_reader :result

      def initialize(result)
        @result = result
        super(result.code)
      end
    end

    class EmailUnavailable < StandardError; end

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

    def email_unavailable?
      User.where.not(id: @user.id).where("LOWER(email) = ?", @email).exists? ||
        EmailChangeRequest.email_reserved?(@email, except_user_id: @user.id)
    end

    def expire_stale_target_requests!
      EmailChangeRequest.pending
        .where("expires_at <= ?", Time.current)
        .where("LOWER(requested_email) = ?", @email)
        .update_all(status: "expired", updated_at: Time.current)
    end

    def supersede_pending_requests!
      EmailChangeRequest.pending.where(user: @user).update_all(
        status: "superseded",
        updated_at: Time.current
      )
    end

    def safe_initiating_session
      return unless @current_session&.user_id == @user.id

      @current_session
    end
  end
end
