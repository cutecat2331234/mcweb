# frozen_string_literal: true

module Identity
  class ConfirmEmailChange < ApplicationService
    def initialize(token:, ip_address: nil, user_agent: nil, at: Time.current)
      @token = token.to_s
      @ip_address = ip_address
      @user_agent = user_agent
      @at = at
    end

    def call
      return invalid_token_failure if @token.blank?
      return invalid_token_failure if rate_limited?

      request = EmailChangeRequest.find_by(
        confirmation_token_digest: digest_token(@token)
      )
      return invalid_token_failure unless request

      outcome = nil
      EmailChangeRequest.transaction do
        EmailAddressLock.acquire!(request.original_email, request.requested_email)
        request.lock!
        request.user.lock!

        if request.confirmed?
          outcome = ServiceResult.success(
            user: request.user,
            email_change_request: request,
            replayed: true,
            revoked_session_count: 0
          )
          next
        end
        unless secure_token?(request.confirmation_token, request.confirmation_token_digest)
          raise InvalidToken
        end
        raise InvalidToken unless request.pending?
        if request.confirmation_expired?(@at)
          request.update!(status: :expired)
          outcome = invalid_token_failure
          next
        end
        unless request.user.email.casecmp?(request.original_email)
          request.update!(status: :superseded)
          outcome = invalid_token_failure
          next
        end
        if User.where.not(id: request.user_id)
               .where("LOWER(email) = ?", request.requested_email.downcase).exists?
          raise EmailUnavailable
        end

        preserve_session_id = active_initiating_session_id(request)
        previous_verified = request.user.email_verified?
        request.user.update!(
          email: request.requested_email,
          email_verified: true,
          email_verified_at: @at,
          developer_mode_email_verified: false,
          email_verification_token: nil,
          email_verification_token_digest: nil,
          email_verification_sent_at: nil
        )
        request.update!(
          status: :confirmed,
          confirmed_at: @at,
          revert_expires_at: @at + EmailChangeRequest::REVERSAL_TTL,
          confirmation_token: nil
        )

        revoked_count = Session.where(user_id: request.user_id, revoked_at: nil)
          .where.not(id: preserve_session_id)
          .update_all(revoked_at: @at, updated_at: @at)

        Administration::AuditLogger.call(
          actor: request.user,
          action: "identity.email_changed",
          resource: request.user,
          metadata: {
            previous_domain: email_domain(request.original_email),
            replacement_domain: email_domain(request.requested_email),
            other_sessions_revoked: revoked_count,
            initiating_session_preserved: preserve_session_id.present?,
            reversal_ttl_seconds: EmailChangeRequest::REVERSAL_TTL.to_i
          },
          before_state: { email_verified: previous_verified },
          after_state: { email_verified: true },
          ip_address: @ip_address,
          user_agent: @user_agent
        )

        outcome = ServiceResult.success(
          user: request.user,
          email_change_request: request,
          replayed: false,
          revoked_session_count: revoked_count
        )
      end
      outcome
    rescue InvalidToken
      invalid_token_failure
    rescue EmailUnavailable, ActiveRecord::RecordNotUnique
      failure("email_not_available")
    rescue ActiveRecord::StaleObjectError
      failure("email_change_conflict")
    end

    class InvalidToken < StandardError; end
    class EmailUnavailable < StandardError; end

    private

    def rate_limited?
      Administration::RateLimiter.call(
        key: "confirm_email_change:#{@ip_address.presence || 'no_ip'}",
        limit: 30,
        window: 15.minutes
      ).failure?
    end

    def active_initiating_session_id(request)
      Session.active.where(user_id: request.user_id, id: request.initiating_session_id).pick(:id)
    end

    def secure_token?(stored_token, stored_digest)
      actual = digest_token(stored_token)
      expected = digest_token(@token)
      secure_match?(actual, expected) && secure_match?(stored_digest.to_s, expected)
    end

    def secure_match?(left, right)
      left.bytesize == right.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(left, right)
    end

    def digest_token(token)
      Digest::SHA256.hexdigest(token.to_s)
    end

    def email_domain(email)
      email.to_s.split("@", 2).last.to_s.downcase
    end

    def invalid_token_failure
      failure("invalid_or_expired_email_change_token")
    end

    def failure(code)
      ServiceResult.failure(error: code, code:)
    end
  end
end
