# frozen_string_literal: true

require "digest"

module Identity
  module SecurityRecoveryMailDelivery
    HANDLER_KEY = "identity.security_recovery_email"
    PASSWORD_RESET = "password_reset"
    TOTP_RECOVERY = "totp_recovery"
    RESEND_COOLDOWN = 2.minutes
    PASSWORD_RESET_TTL = 1.hour
    TOTP_RECOVERY_TTL = 30.minutes
    TOKEN_DIGEST_PATTERN = /\A[0-9a-f]{64}\z/

    DeliveryRequest = Data.define(:user, :token, :intent, :reused)

    class AuditFailed < StandardError
      attr_reader :result

      def initialize(result)
        @result = result
        super(result.code.presence || "security_recovery_delivery_audit_failed")
      end
    end

    PURPOSES = {
      PASSWORD_RESET => {
        token_attribute: :password_reset_token,
        digest_attribute: :password_reset_token_digest,
        sent_at_attribute: :password_reset_sent_at,
        ttl: PASSWORD_RESET_TTL,
        mail_method: :password_reset_email,
        requested_action: "identity.password_reset_requested"
      }.freeze,
      TOTP_RECOVERY => {
        token_attribute: :totp_recovery_token,
        digest_attribute: :totp_recovery_token_digest,
        sent_at_attribute: :totp_recovery_sent_at,
        ttl: TOTP_RECOVERY_TTL,
        mail_method: :totp_recovery_email,
        requested_action: "identity.totp_recovery_requested"
      }.freeze
    }.freeze

    module_function

    def register(registry)
      registry.register(
        key: HANDLER_KEY,
        source_kind: "user",
        queue: "mailers",
        replay_contract: "at_least_once",
        lease: 5.minutes,
        max_attempts: 5,
        retry_delays: [ 30.seconds, 2.minutes, 5.minutes, 15.minutes ],
        manual_reopen_permission: "system.jobs.manage",
        argument_schema: {
          "purpose" => {
            type: "string",
            required: true,
            maximum: 32,
            pattern: /\A(?:password_reset|totp_recovery)\z/
          },
          "token_digest" => {
            type: "string",
            required: true,
            maximum: 64,
            pattern: TOKEN_DIGEST_PATTERN
          }
        }
      ) do |intent, _context|
        deliver(intent)
      end
    end

    def issue!(user:, purpose:, ip_address: nil, user_agent: nil, now: Time.current)
      purpose = purpose.to_s
      config = purpose_config!(purpose)
      request = nil

      User.transaction do
        locked_user = User.lock.find(user.id)
        unless eligible?(locked_user, purpose)
          raise Operations::DurableEnqueue::InvalidRequest,
                "security_recovery_delivery_source_ineligible"
        end

        token, reused = current_or_rotated_token(locked_user, config:, now:)
        token_digest = digest_token(token)
        intent = Operations::DurableEnqueue.record!(
          handler: HANDLER_KEY,
          source_id: locked_user.id,
          dedupe_key: "identity-security-recovery:#{purpose}:#{locked_user.id}:#{token_digest}",
          arguments: { purpose:, token_digest: },
          requested_at: now
        )
        delivery_status = status(intent).fetch(:status)

        audit_result = Administration::AuditLogger.call(
          actor: nil,
          action: config.fetch(:requested_action),
          resource: locked_user,
          metadata: {
            delivery: "verified_email",
            delivery_purpose: purpose,
            delivery_intent_public_id: intent.public_id,
            delivery_status: delivery_status,
            request_kind: reused ? "duplicate" : "issued",
            requester: "anonymous"
          },
          ip_address:,
          user_agent:
        )
        raise AuditFailed, audit_result if audit_result.failure?

        request = DeliveryRequest.new(
          user: locked_user,
          token:,
          intent:,
          reused:
        )
      end

      request
    end

    def deliver(intent)
      arguments = intent.arguments
      purpose = arguments.respond_to?(:[]) ? arguments["purpose"].to_s : ""
      expected_digest = arguments.respond_to?(:[]) ? arguments["token_digest"].to_s : ""
      config = PURPOSES[purpose]
      unless config && expected_digest.match?(TOKEN_DIGEST_PATTERN)
        return skipped("recovery_delivery_invalid")
      end

      User.transaction do
        user = User.lock.find_by(id: intent.source_id)
        next skipped("source_missing") unless user
        next skipped("source_ineligible") unless eligible?(user, purpose)

        token = user.public_send(config.fetch(:token_attribute)).to_s
        stored_digest = user.public_send(config.fetch(:digest_attribute)).to_s
        sent_at = user.public_send(config.fetch(:sent_at_attribute))
        next skipped("recovery_token_missing") if token.blank? || stored_digest.blank?
        if sent_at.blank? || sent_at < config.fetch(:ttl).ago
          next skipped("recovery_token_expired")
        end

        actual_digest = digest_token(token)
        unless secure_match?(actual_digest, expected_digest) &&
            secure_match?(stored_digest, expected_digest)
          next skipped("recovery_token_superseded")
        end

        # Keep token rotation behind the same user-row lock until the transport
        # accepts this message. Delivery exceptions must escape so the durable
        # dispatcher can apply its bounded retry/dead-letter policy.
        Identity::Mailer.public_send(config.fetch(:mail_method), user.id, token).deliver_now
        Operations::DurableEnqueueResult.succeeded
      end
    end

    def status(intent)
      durable = Operations::DurableEnqueueStatus.call(intent)
      durable_status = durable.fetch(:status)
      public_status = case durable_status
      when "succeeded" then "sent"
      when "skipped", "dead_lettered" then "failed"
      else "pending"
      end

      durable.merge(
        status: public_status,
        durable_status: durable_status,
        retryable: durable_status == "dead_lettered",
        reason_code: durable[:last_error_code]
      )
    end

    def recent_statuses(limit: 25)
      Operations::DurableEnqueueIntent
        .where(handler_key: HANDLER_KEY)
        .order(requested_at: :desc, id: :desc)
        .limit(limit.to_i.clamp(1, 100))
        .map do |intent|
          projected = status(intent)
          {
            public_id: projected.fetch(:public_id),
            user_id: intent.source_id,
            purpose: intent.arguments.fetch("purpose"),
            status: projected.fetch(:status),
            durable_status: projected.fetch(:durable_status),
            retryable: projected.fetch(:retryable),
            attempt_count: projected.fetch(:attempt_count),
            requested_at: projected[:requested_at],
            last_event_at: projected[:last_event_at],
            reason_code: projected[:reason_code]
          }
        end
    end

    def clear_attributes(purpose)
      config = purpose_config!(purpose)
      {
        config.fetch(:token_attribute) => nil,
        config.fetch(:digest_attribute) => nil,
        config.fetch(:sent_at_attribute) => nil
      }
    end

    def current_or_rotated_token(user, config:, now:)
      token = user.public_send(config.fetch(:token_attribute)).to_s
      stored_digest = user.public_send(config.fetch(:digest_attribute)).to_s
      sent_at = user.public_send(config.fetch(:sent_at_attribute))
      current_digest = digest_token(token) if token.present?
      reusable = token.present? &&
        sent_at.present? &&
        sent_at > now - RESEND_COOLDOWN &&
        secure_match?(stored_digest, current_digest.to_s)
      return [ token, true ] if reusable

      token = SecureRandom.urlsafe_base64(32)
      user.update!(
        config.fetch(:token_attribute) => token,
        config.fetch(:digest_attribute) => digest_token(token),
        config.fetch(:sent_at_attribute) => now
      )
      [ token, false ]
    end
    private_class_method :current_or_rotated_token

    def eligible?(user, purpose)
      return false if user.deleted?
      return true if purpose == PASSWORD_RESET

      user.active? && user.email_verified? && user.totp_enabled?
    end
    private_class_method :eligible?

    def purpose_config!(purpose)
      PURPOSES.fetch(purpose.to_s) do
        raise Operations::DurableEnqueue::InvalidRequest,
              "security_recovery_delivery_purpose_invalid"
      end
    end
    private_class_method :purpose_config!

    def digest_token(token)
      Digest::SHA256.hexdigest(token.to_s)
    end
    private_class_method :digest_token

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
