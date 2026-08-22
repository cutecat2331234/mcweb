# frozen_string_literal: true

module Identity
  module EmailChangeDelivery
    HANDLER_KEY = "identity.email_change_notice"
    CONFIRMATION = "confirmation"
    SECURITY_NOTICE = "security_notice"

    module_function

    def register(registry)
      registry.register(
        key: HANDLER_KEY,
        source_kind: "identity.email_change_request",
        queue: "mailers",
        replay_contract: "at_least_once",
        lease: 5.minutes,
        max_attempts: 5,
        retry_delays: [ 1.minute, 5.minutes, 30.minutes, 2.hours ],
        argument_schema: {
          "kind" => {
            type: "string",
            required: true,
            maximum: 32,
            pattern: /\A(?:confirmation|security_notice)\z/
          },
          "token_digest" => {
            type: "string",
            required: true,
            maximum: 64,
            pattern: /\A[0-9a-f]{64}\z/
          }
        }
      ) do |intent, _context|
        deliver(intent)
      end
    end

    def record!(request:, confirmation_token:, revocation_token:)
      record_notice!(request:, kind: CONFIRMATION, token: confirmation_token)
      record_notice!(request:, kind: SECURITY_NOTICE, token: revocation_token)
    end

    def deliver(intent)
      request = EmailChangeRequest.find_by(id: intent.source_id)
      return skipped("source_missing") unless request

      kind = intent.arguments.fetch("kind")
      expected_digest = intent.arguments.fetch("token_digest")
      case kind
      when CONFIRMATION
        return skipped("email_change_not_pending") unless request.pending?
        return skipped("email_change_expired") if request.confirmation_expired?

        token = request.confirmation_token.to_s
        return skipped("email_change_token_superseded") unless token_matches?(
          token,
          request.confirmation_token_digest,
          expected_digest
        )

        Identity::Mailer.email_change_confirmation(request.id, token).deliver_now
      when SECURITY_NOTICE
        return skipped("email_change_notice_obsolete") unless revocation_available?(request)

        token = request.revocation_token.to_s
        return skipped("email_change_token_superseded") unless token_matches?(
          token,
          request.revocation_token_digest,
          expected_digest
        )

        Identity::Mailer.email_change_security_notice(request.id, token).deliver_now
      else
        return skipped("email_change_notice_kind_invalid")
      end

      Operations::DurableEnqueueResult.succeeded
    end

    def record_notice!(request:, kind:, token:)
      token_digest = Digest::SHA256.hexdigest(token.to_s)
      stored_digest = kind == CONFIRMATION ?
        request.confirmation_token_digest : request.revocation_token_digest
      unless token.present? && secure_match?(stored_digest.to_s, token_digest)
        raise Operations::DurableEnqueue::InvalidRequest,
              "email_change_delivery_token_mismatch"
      end

      Operations::DurableEnqueue.record!(
        handler: HANDLER_KEY,
        source_id: request.id,
        dedupe_key: "email-change:#{request.id}:#{kind}:#{token_digest}",
        arguments: { kind:, token_digest: }
      )
    end
    private_class_method :record_notice!

    def revocation_available?(request)
      (request.pending? && !request.confirmation_expired?) ||
        (request.confirmed? && !request.reversal_expired?)
    end
    private_class_method :revocation_available?

    def token_matches?(token, stored_digest, expected_digest)
      return false if token.blank?

      actual_digest = Digest::SHA256.hexdigest(token)
      secure_match?(actual_digest, expected_digest) &&
        secure_match?(stored_digest.to_s, expected_digest)
    end
    private_class_method :token_matches?

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
