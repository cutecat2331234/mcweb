# frozen_string_literal: true

module Minecraft
  class AuthorizeWorldRestore < ApplicationService
    PURPOSE = "minecraft_world_restore_authorization_v1"
    EXPIRES_IN = 5.minutes
    NONCE_PATTERN = /\A[0-9a-f]{32}\z/
    ALLOWED_METHODS = %w[password totp recovery_code].freeze

    class << self
      def verify(token, plan:, actor:)
        payload = verifier.verified(token.to_s, purpose: PURPOSE)
        return failure(:world_restore_authorization_invalid) unless payload.is_a?(Hash)
        return failure(:world_restore_authorization_invalid) unless payload["nonce"].to_s.match?(NONCE_PATTERN)
        return failure(:world_restore_authorization_invalid) unless ALLOWED_METHODS.include?(payload["authorization_method"].to_s)

        expected = token_payload(
          plan: plan,
          actor: actor,
          method: payload["authorization_method"],
          authorized_at: plan.authorized_at
        )
        valid = expected.all? { |key, value| secure_match?(payload[key], value) }
        valid && secure_match?(Digest::SHA256.hexdigest(token.to_s), plan.authorization_digest) ?
          ServiceResult.success(authorization_method: payload["authorization_method"]) :
          failure(:world_restore_authorization_invalid)
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        failure(:world_restore_authorization_invalid)
      end

      def token_payload(plan:, actor:, method:, authorized_at:, lock_version: plan.lock_version)
        {
          "actor_id" => actor&.id.to_s,
          "plan_id" => plan.public_id,
          "plan_digest" => plan.plan_digest,
          "backup_manifest_digest" => plan.backup_manifest_digest,
          "server_configuration_digest" => plan.server_configuration_digest,
          "node_capability_digest" => plan.node_capability_digest,
          "reason_digest" => Digest::SHA256.hexdigest(plan.reason),
          "plan_lock_version" => lock_version.to_s,
          "authorization_method" => method.to_s,
          "authorized_at" => authorized_at&.utc&.iso8601(6).to_s
        }
      end

      private

      def verifier
        Rails.application.message_verifier(PURPOSE)
      end

      def secure_match?(left, right)
        left = left.to_s
        right = right.to_s
        left.bytesize == right.bytesize && ActiveSupport::SecurityUtils.secure_compare(left, right)
      end

      def failure(code)
        ServiceResult.failure(error: code, code: code)
      end
    end

    RATE_LIMIT_SCOPE = "minecraft_world_restore_authorize"

    def initialize(plan:, actor:, password:, code: nil, ip_address: nil)
      @plan = plan
      @actor = actor
      @password = password
      @code = code
      @ip_address = ip_address
    end

    def call
      return failure(:world_restore_unauthorized) unless @actor&.id == @plan.actor_id

      result = nil
      Minecraft::WorldRestorePlan.transaction do
        @plan.lock!
        unless @plan.status_planned? || @plan.status_authorized?
          result = failure(:world_restore_plan_not_authorizable)
          next
        end
        if (error = Minecraft::PlanWorldRestore.current_contract_error(@plan, actor: @actor))
          expire_plan! if error == :world_restore_plan_expired
          result = failure(error)
          next
        end

        throttle = sensitive_action_limit(:check)
        if throttle.failure?
          audit_authorization_failure(rate_limited: true)
          result = ServiceResult.failure(
            error: :world_restore_authorization_rate_limited,
            code: :rate_limited,
            retry_after: throttle.retry_after
          )
          next
        end

        verification = Identity::SensitiveActionVerifier.call(
          user: @actor,
          password: @password,
          code: @code
        )
        if verification.failure?
          sensitive_action_limit(:failure)
          audit_authorization_failure(rate_limited: false)
          result = failure(:world_restore_authorization_failed)
          next
        end
        sensitive_action_limit(:success)

        method = verification.value.fetch(:method)
        authorized_at = Time.current
        @plan.assign_attributes(
          status: "authorized",
          authorization_method: method,
          authorization_expires_at: authorized_at + EXPIRES_IN,
          authorized_at: authorized_at,
          authorization_consumed_at: nil
        )
        payload = self.class.token_payload(
          plan: @plan,
          actor: @actor,
          method: method,
          authorized_at: authorized_at,
          lock_version: @plan.lock_version + 1
        ).merge("nonce" => SecureRandom.hex(16))
        token = Rails.application.message_verifier(PURPOSE)
          .generate(payload, purpose: PURPOSE, expires_in: EXPIRES_IN)

        @plan.authorization_digest = Digest::SHA256.hexdigest(token)
        @plan.save!(touch: true)
        append_event("minecraft.world_restore.authorized", "authorized", method: method)
        AuditLog.record!(
          action: "minecraft.world_restore.authorized",
          actor: @actor,
          resource: @plan,
          reason: @plan.reason,
          request_id: @plan.request_id,
          metadata: safe_metadata.merge(authorization_method: method)
        )
        result = ServiceResult.success(
          authorization_token: token,
          authorization_method: method,
          confirmation: Minecraft::PlanWorldRestore.confirmation_for(@plan),
          request_id: @plan.request_id,
          expires_in: EXPIRES_IN.to_i
        )
      end
      result || failure(:world_restore_authorization_failed)
    rescue ActiveRecord::StaleObjectError
      failure(:world_restore_stale)
    rescue AuthorizationError => error
      failure(error.message.to_sym)
    end

    private

    class AuthorizationError < StandardError; end

    def expire_plan!
      @plan.update!(status: "expired", failed_at: Time.current, error_code: "world_restore_plan_expired")
      append_event("minecraft.world_restore.expired", "expired")
      AuditLog.record!(
        action: "minecraft.world_restore.expired",
        actor: @actor,
        resource: @plan,
        reason: @plan.reason,
        request_id: @plan.request_id,
        metadata: safe_metadata
      )
    end

    def append_event(event_type, phase, payload = {})
      result = Minecraft::AppendWorldRestoreEvent.call(
        plan: @plan,
        event_type: event_type,
        phase: phase,
        actor: @actor,
        payload: safe_metadata.merge(payload)
      )
      raise AuthorizationError, "world_restore_event_ledger_failed" if result.failure?
    end

    def safe_metadata
      {
        plan_id: @plan.public_id,
        server_id: @plan.server.public_id,
        backup_id: @plan.world_backup.public_id,
        request_id: @plan.request_id,
        status: @plan.status
      }
    end

    def sensitive_action_limit(action)
      Administration::SensitiveActionRateLimit.call(
        scope: RATE_LIMIT_SCOPE,
        user: @actor,
        ip_address: @ip_address,
        action: action
      )
    end

    def audit_authorization_failure(rate_limited:)
      AuditLog.record!(
        action: "minecraft.world_restore.authorization_failed",
        actor: @actor,
        resource: @plan,
        reason: @plan.reason,
        request_id: @plan.request_id,
        metadata: safe_metadata.merge(
          rate_limited: rate_limited,
          ip_digest: Digest::SHA256.hexdigest(@ip_address.to_s)[0, 12]
        )
      )
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
