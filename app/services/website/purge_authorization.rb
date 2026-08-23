# frozen_string_literal: true

module Website
  class PurgeAuthorization < ApplicationService
    include LifecycleContract

    PURPOSE = "website_content_final_purge"
    EXPIRES_IN = 5.minutes
    NONCE_PATTERN = /\A[0-9a-f]{32}\z/

    def initialize(actor:, content:, reason:, request_id:, password: nil, code: nil,
                   authorization_token: nil)
      @actor = actor
      @content = content
      @reason = reason
      @request_id = request_id
      @password = password
      @code = code
      @authorization_token = authorization_token
    end

    def call
      unless @actor&.permission?("website.content.purge")
        raise LifecycleError, "website_content_purge_unauthorized"
      end

      reason = normalize_reason!(@reason)
      request_id = normalize_idempotency_key!(@request_id)
      content = @content.class.with_lifecycle.find(@content.id)
      raise LifecycleError, "website_content_not_discarded" unless content.discarded?

      eligibility = PurgeEligibility.call(content: content)
      blockers = eligibility.value.fetch(:blockers)
      unless blockers.empty?
        raise LifecycleError.new("website_content_purge_blocked", blockers: blockers)
      end

      return verify_token(content, reason, request_id) if @authorization_token.present?

      verification = Identity::SensitiveActionVerifier.call(
        user: @actor,
        password: @password,
        code: @code
      )
      return verification if verification.failure?

      method = verification.value.fetch(:method)
      payload = token_payload(content, reason, request_id, method).merge(
        "nonce" => SecureRandom.hex(16)
      )
      token = Rails.application.message_verifier(PURPOSE)
        .generate(payload, purpose: PURPOSE, expires_in: EXPIRES_IN)

      ServiceResult.success(
        authorization_token: token,
        authorization_method: method,
        confirmation: FinalPurge.confirmation_for(content),
        request_id: request_id,
        expires_in: EXPIRES_IN.to_i
      )
    rescue LifecycleError => error
      failure(error)
    end

    private

    def verify_token(content, reason, request_id)
      payload = Rails.application.message_verifier(PURPOSE)
        .verified(@authorization_token.to_s, purpose: PURPOSE)
      unless payload.is_a?(Hash) && payload["nonce"].to_s.match?(NONCE_PATTERN)
        raise LifecycleError, "website_content_purge_authorization_invalid"
      end

      method = payload["authorization_method"].to_s
      expected = token_payload(content, reason, request_id, method)
      valid = expected.all? { |key, value| secure_match?(payload[key], value) }
      unless valid && %w[password totp recovery_code].include?(method)
        raise LifecycleError, "website_content_purge_authorization_invalid"
      end

      ServiceResult.success(authorization_method: method)
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      failure(LifecycleError.new("website_content_purge_authorization_invalid"))
    end

    def token_payload(content, reason, request_id, method)
      {
        "actor_id" => @actor.id.to_s,
        "content_type" => content.class.name,
        "content_id" => content.id.to_s,
        "content_lock_version" => content.lock_version.to_s,
        "reason_digest" => Digest::SHA256.hexdigest(reason),
        "request_id_digest" => idempotency_digest(request_id),
        "authorization_method" => method.to_s
      }
    end

    def secure_match?(left, right)
      left = left.to_s
      right = right.to_s
      left.bytesize == right.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(left, right)
    end
  end
end
