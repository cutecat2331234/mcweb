# frozen_string_literal: true

module Minecraft
  class AuthorizeWorldRestoreRecovery < ApplicationService
    PURPOSE = "minecraft_world_restore_recovery_authorization_v1"
    EXPIRES_IN = 5.minutes
    NONCE_PATTERN = /\A[0-9a-f]{32}\z/
    ALLOWED_METHODS = %w[password totp recovery_code].freeze
    RATE_LIMIT_SCOPE = "minecraft_world_restore_recovery_authorize"

    class << self
      def verify(token, resolution:, actor:)
        payload = verifier.verified(token.to_s, purpose: PURPOSE)
        return failure(:world_restore_recovery_authorization_invalid) unless payload.is_a?(Hash)
        return failure(:world_restore_recovery_authorization_invalid) unless payload["nonce"].to_s.match?(NONCE_PATTERN)
        return failure(:world_restore_recovery_authorization_invalid) unless ALLOWED_METHODS.include?(
          payload["authorization_method"].to_s
        )

        expected = token_payload(
          resolution: resolution,
          actor: actor,
          method: payload["authorization_method"],
          authorized_at: resolution.authorized_at
        )
        valid = expected.all? { |key, value| secure_match?(payload[key], value) }
        valid && secure_match?(Digest::SHA256.hexdigest(token.to_s), resolution.authorization_digest) ?
          ServiceResult.success(authorization_method: payload["authorization_method"]) :
          failure(:world_restore_recovery_authorization_invalid)
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        failure(:world_restore_recovery_authorization_invalid)
      end

      def token_payload(resolution:, actor:, method:, authorized_at:, lock_version: resolution.lock_version)
        plan = resolution.restore_plan
        {
          "actor_id" => actor&.id.to_s,
          "resolution_id" => resolution.public_id,
          "plan_id" => plan.public_id,
          "plan_digest" => resolution.plan_digest,
          "server_configuration_digest" => resolution.server_configuration_digest,
          "node_capability_digest" => resolution.node_capability_digest,
          "resolution_action" => resolution.resolution_action,
          "reason_digest" => Digest::SHA256.hexdigest(resolution.reason),
          "resolution_lock_version" => lock_version.to_s,
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

    def initialize(resolution:, actor:, password:, code: nil, ip_address: nil, expected_lock_version:)
      @resolution = resolution
      @plan = resolution.restore_plan
      @actor = actor
      @password = password
      @code = code
      @ip_address = ip_address
      @expected_lock_version = Integer(expected_lock_version, exception: false)
    end

    def call
      return failure(:world_restore_recovery_unauthorized) unless @actor&.permission?(
        Minecraft::PlanWorldRestoreRecovery::PERMISSION
      ) && @resolution.actor_id == @actor.id
      return failure(:world_restore_recovery_lock_version_required) if @expected_lock_version.nil?

      result = nil
      Minecraft::WorldRestorePlan.transaction do
        @plan.lock!
        server = Minecraft::Server.lock.find(@plan.server_id)
        node = Minecraft::Node.lock.find(@plan.node_id)
        server.association(:node).target = node
        @plan.association(:server).target = server
        @plan.association(:node).target = node
        @resolution = @plan.recovery_resolutions.lock.find(@resolution.id)

        if @resolution.expired_by_time?
          Minecraft::ExpireWorldRestoreRecoveryResolution.expire_locked!(@resolution)
          result = failure(:world_restore_recovery_resolution_expired)
          next
        end
        unless @resolution.status_planned? || @resolution.status_authorized?
          result = failure(:world_restore_recovery_not_authorizable)
          next
        end
        unless @resolution.lock_version == @expected_lock_version
          result = failure(:world_restore_recovery_stale)
          next
        end
        if (error = Minecraft::PlanWorldRestoreRecovery.current_contract_error(
          @plan,
          actor: @actor,
          server: server,
          node: node,
          action: @resolution.resolution_action
        ))
          result = failure(error)
          next
        end
        unless node.world_recovery_capability_digest == @resolution.node_capability_digest
          result = failure(:world_restore_recovery_capability_changed)
          next
        end

        reservation = sensitive_action_reserve
        if reservation.failure?
          audit_failure(rate_limited: true)
          result = ServiceResult.failure(
            error: :world_restore_recovery_authorization_rate_limited,
            code: :rate_limited,
            retry_after: reservation.retry_after
          )
          next
        end
        reservation_id = reservation.value.fetch(:reservation_id)
        verification = Identity::SensitiveActionVerifier.call(
          user: @actor,
          password: @password,
          code: @code
        )
        if verification.failure?
          sensitive_action_settle(:failure, reservation_id)
          audit_failure(rate_limited: false)
          result = failure(:world_restore_recovery_authorization_failed)
          next
        end
        settlement = sensitive_action_settle(:success, reservation_id)
        if settlement.failure?
          audit_failure(rate_limited: false)
          result = failure(:world_restore_recovery_authorization_failed)
          next
        end

        method = verification.value.fetch(:method)
        authorized_at = Time.current
        expires_at = [ authorized_at + EXPIRES_IN, @resolution.expires_at ].min
        if expires_at <= authorized_at
          Minecraft::ExpireWorldRestoreRecoveryResolution.expire_locked!(@resolution, force: true)
          result = failure(:world_restore_recovery_resolution_expired)
          next
        end
        @resolution.assign_attributes(
          status: "authorized",
          authorization_method: method,
          authorization_expires_at: expires_at,
          authorized_at: authorized_at,
          authorization_consumed_at: nil
        )
        payload = self.class.token_payload(
          resolution: @resolution,
          actor: @actor,
          method: method,
          authorized_at: authorized_at,
          lock_version: @resolution.lock_version + 1
        ).merge("nonce" => SecureRandom.hex(16))
        token = Rails.application.message_verifier(PURPOSE)
          .generate(payload, purpose: PURPOSE, expires_in: expires_at - authorized_at)
        @resolution.authorization_digest = Digest::SHA256.hexdigest(token)
        @resolution.save!(touch: true)
        append_event!("minecraft.world_restore.recovery_resolution_authorized", authorization_method: method)
        audit!("minecraft.world_restore.recovery_resolution_authorized", authorization_method: method)
        result = ServiceResult.success(
          authorization_token: token,
          authorization_method: method,
          confirmation: Minecraft::PlanWorldRestoreRecovery.confirmation_for(@resolution),
          request_id: @resolution.request_id,
          expires_in: (expires_at - authorized_at).floor,
          resolution: @resolution
        )
      end
      result || failure(:world_restore_recovery_authorization_failed)
    rescue ActiveRecord::StaleObjectError
      failure(:world_restore_recovery_stale)
    rescue Minecraft::ExpireWorldRestoreRecoveryResolution::ExpirationError => error
      failure(error.message.to_sym)
    rescue AuthorizationError => error
      failure(error.message.to_sym)
    end

    private

    class AuthorizationError < StandardError; end

    def sensitive_action_reserve
      Administration::SensitiveActionRateLimit.call(
        scope: RATE_LIMIT_SCOPE,
        user: @actor,
        ip_address: @ip_address,
        context: @resolution.public_id,
        action: :reserve
      )
    end

    def sensitive_action_settle(action, reservation_id)
      Administration::SensitiveActionRateLimit.call(
        scope: RATE_LIMIT_SCOPE,
        user: @actor,
        action: action,
        reservation_id: reservation_id
      )
    end

    def audit_failure(rate_limited:)
      audit!(
        "minecraft.world_restore.recovery_resolution_authorization_failed",
        rate_limited: rate_limited,
        ip_digest: Digest::SHA256.hexdigest(@ip_address.to_s)[0, 12]
      )
    end

    def append_event!(event_type, payload = {})
      result = Minecraft::AppendWorldRestoreEvent.call(
        plan: @plan,
        event_type: event_type,
        phase: "recovery_required",
        actor: @actor,
        payload: audit_metadata.merge(payload)
      )
      raise AuthorizationError, "world_restore_event_ledger_failed" if result.failure?
    end

    def audit!(action, payload = {})
      AuditLog.record!(
        action: action,
        actor: @actor,
        resource: @plan,
        reason: @resolution.reason,
        request_id: @resolution.request_id,
        metadata: audit_metadata.merge(payload)
      )
    end

    def audit_metadata
      {
        plan_id: @plan.public_id,
        server_id: @plan.server.public_id,
        resolution_id: @resolution.public_id,
        resolution_action: @resolution.resolution_action,
        resolution_status: @resolution.status
      }
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
