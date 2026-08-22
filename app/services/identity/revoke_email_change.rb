# frozen_string_literal: true

module Identity
  class RevokeEmailChange < ApplicationService
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
        revocation_token_digest: digest_token(@token)
      )
      return invalid_token_failure unless request

      outcome = nil
      EmailChangeRequest.transaction do
        EmailAddressLock.acquire!(request.original_email, request.requested_email)
        request.lock!
        request.user.lock!

        if request.revoked?
          outcome = ServiceResult.success(
            user: request.user,
            email_change_request: request,
            replayed: true,
            reverted: request.reverted_at.present?
          )
          next
        end
        raise InvalidToken unless secure_token?(request.revocation_token, request.revocation_token_digest)

        previous_status = request.status
        case request.status
        when "pending"
          if request.confirmation_expired?(@at)
            request.update!(status: :expired)
            outcome = invalid_token_failure
            next
          end

          request.update!(status: :revoked, revocation_token: nil)
          reverted = false
        when "confirmed"
          raise ExpiredToken if request.reversal_expired?(@at)
          unless request.user.email.casecmp?(request.requested_email)
            raise InvalidToken
          end
          if User.where.not(id: request.user_id)
                 .where("LOWER(email) = ?", request.original_email.downcase).exists?
            raise EmailUnavailable
          end

          request.user.update!(
            email: request.original_email,
            email_verified: request.original_email_verified,
            email_verified_at: request.original_email_verified_at,
            developer_mode_email_verified: false,
            email_verification_token: nil,
            email_verification_token_digest: nil,
            email_verification_sent_at: nil
          )
          Session.where(user_id: request.user_id, revoked_at: nil)
            .update_all(revoked_at: @at, updated_at: @at)
          request.update!(
            status: :revoked,
            reverted_at: @at,
            revocation_token: nil
          )
          reverted = true
        else
          raise InvalidToken
        end

        Administration::AuditLogger.call(
          actor: request.user,
          action: "identity.email_change_revoked",
          resource: request,
          metadata: {
            reverted:,
            original_domain: email_domain(request.original_email),
            requested_domain: email_domain(request.requested_email),
            all_sessions_revoked: reverted
          },
          before_state: { status: previous_status },
          after_state: { status: "revoked", reverted: },
          ip_address: @ip_address,
          user_agent: @user_agent
        )

        outcome = ServiceResult.success(
          user: request.user,
          email_change_request: request,
          replayed: false,
          reverted:
        )
      end
      outcome
    rescue InvalidToken, ExpiredToken
      invalid_token_failure
    rescue EmailUnavailable, ActiveRecord::RecordNotUnique
      failure("email_not_available")
    rescue ActiveRecord::StaleObjectError
      failure("email_change_conflict")
    end

    class InvalidToken < StandardError; end
    class ExpiredToken < StandardError; end
    class EmailUnavailable < StandardError; end

    private

    def rate_limited?
      Administration::RateLimiter.call(
        key: "revoke_email_change:#{@ip_address.presence || 'no_ip'}",
        limit: 30,
        window: 15.minutes
      ).failure?
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
