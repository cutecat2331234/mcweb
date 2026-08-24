# frozen_string_literal: true

require "digest"

module Minecraft
  class SetPlayerAccessRule < ApplicationService
    IDEMPOTENCY_KEY_PATTERN = /\A[^[:cntrl:]]{8,200}\z/
    UUID_PATTERN = /\A[0-9a-f]{32}\z/i

    def initialize(
      server:,
      actor: nil,
      desired_state:,
      rule_type: nil,
      username: nil,
      player_uuid: nil,
      reason:,
      expires_at: nil,
      idempotency_key:,
      rule: nil,
      expected_lock_version: nil,
      request_context: {},
      now: Time.current
    )
      @server = server
      @actor = actor
      @desired_state = desired_state
      @rule_type = (rule&.rule_type || rule_type).to_s
      @username = (rule&.username || username).to_s.strip
      @player_uuid_input = rule&.player_uuid || player_uuid
      @reason = reason.to_s.strip
      @expiry_input = expires_at
      @expires_at = normalize_expiry(expires_at)
      @idempotency_key = idempotency_key.to_s
      @rule = rule
      @expected_lock_version = expected_lock_version
      @request_context = request_context.to_h.symbolize_keys.slice(:ip_address, :user_agent, :request_id)
      @now = now
    end

    def call
      validation = validate_request
      return validation if validation

      @desired_state ? apply_rule : revoke_rule
    rescue ActiveRecord::RecordNotUnique
      replay_after_conflict
    rescue ActiveRecord::StaleObjectError
      failure(:minecraft_access_rule_stale)
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(
        errors: error.record.errors.to_hash,
        error: :minecraft_access_rule_invalid,
        code: :minecraft_access_rule_invalid
      )
    end

    private

    def validate_request
      return failure(:minecraft_access_rule_state_required) unless [ true, false ].include?(@desired_state)
      return failure(:minecraft_access_rule_type_invalid) unless @rule_type.in?(Minecraft::PlayerAccessRule::RULE_TYPES)
      return failure(:minecraft_access_rule_username_invalid) unless @username.match?(Minecraft::PlayerAccessRule::USERNAME_PATTERN)
      return failure(:minecraft_access_rule_reason_invalid) unless valid_reason?
      return failure(:minecraft_access_rule_idempotency_invalid) unless @idempotency_key.match?(IDEMPOTENCY_KEY_PATTERN)
      return failure(:minecraft_access_rule_uuid_invalid) if @player_uuid_input.present? && normalized_uuid.nil?
      return failure(:minecraft_access_rule_expiry_invalid) if @desired_state && invalid_expiry?
      failure(:minecraft_access_rule_lock_version_required) if !@desired_state && @actor && @expected_lock_version.nil?
    end

    def valid_reason?
      @reason.length.between?(1, 500) && !@reason.match?(/[[:cntrl:]]/)
    end

    def invalid_expiry?
      (@expiry_input.present? && @expires_at.nil?) || (@expires_at.present? && @expires_at <= @now)
    end

    def normalize_expiry(value)
      return if value.blank?
      return value.in_time_zone if value.respond_to?(:in_time_zone)

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def normalized_uuid
      return @normalized_uuid if defined?(@normalized_uuid)
      return @normalized_uuid = nil if @player_uuid_input.blank?

      compact = @player_uuid_input.to_s.delete("-")
      return @normalized_uuid = nil unless compact.match?(UUID_PATTERN)

      @normalized_uuid = [ 8, 4, 4, 4, 12 ].map do |length|
        compact.slice!(0, length)
      end.join("-").downcase
    end

    def apply_rule
      digest = idempotency_digest("apply")
      replay = Minecraft::PlayerAccessRule.find_by(apply_idempotency_key_digest: digest)
      return replay_result(replay, operation: :apply) if replay

      outcome = nil
      Minecraft::PlayerAccessRule.transaction do
        @server.lock!
        existing = effective_rule_scope.lock.first
        if existing
          outcome = equivalent_apply?(existing) ?
            success(existing, replayed: false, noop: true) :
            failure(:minecraft_access_rule_conflict, value: { rule: existing })
          next
        end

        rule = Minecraft::PlayerAccessRule.create!(
          server: @server,
          created_by: @actor,
          rule_type: @rule_type,
          username: @username,
          player_uuid: normalized_uuid,
          reason: @reason,
          expires_at: @expires_at,
          apply_idempotency_key_digest: digest,
          status: "pending_apply"
        )
        delivery = Minecraft::EnqueueConsoleCommand.call(
          server: @server,
          command: apply_command,
          delivery_prefix: "player-access-#{rule.public_id}-apply"
        )
        unless delivery.success?
          rule.update!(status: "failed", failed_at: @now)
          audit(rule, "minecraft.player_access_rule.apply_failed", before_state: {}, after_state: state(rule))
          outcome = ServiceResult.failure(
            error: delivery.error || :minecraft_access_rule_delivery_failed,
            code: :minecraft_access_rule_delivery_failed,
            value: { rule: rule }
          )
          next
        end

        task = delivery.value.fetch(:task)
        rule.update!(apply_task: task)
        audit(rule, "minecraft.player_access_rule.apply_queued", before_state: {}, after_state: state(rule))
        Minecraft::ReconcilePlayerAccessRule.call(task:) if task.completed? || task.failed?
        outcome = success(rule.reload, replayed: false, noop: false)
      end
      outcome
    end

    def revoke_rule
      digest = idempotency_digest("revoke")
      replay = Minecraft::PlayerAccessRule.find_by(revoke_idempotency_key_digest: digest)
      return replay_result(replay, operation: :revoke) if replay

      outcome = nil
      Minecraft::PlayerAccessRule.transaction do
        @server.lock!
        rule = resolve_rule_for_revoke
        unless rule
          outcome = success(nil, replayed: false, noop: true)
          next
        end

        rule.lock!
        if @expected_lock_version && rule.lock_version != @expected_lock_version.to_i
          outcome = failure(:minecraft_access_rule_stale, value: { rule: rule })
          next
        end
        if rule.revoked?
          outcome = success(rule, replayed: false, noop: true)
          next
        elsif rule.failed?
          outcome = failure(:minecraft_access_rule_not_active, value: { rule: rule })
          next
        elsif rule.pending_apply?
          outcome = failure(:minecraft_access_rule_apply_pending, value: { rule: rule })
          next
        elsif rule.pending_revoke?
          outcome = failure(:minecraft_access_rule_revoke_pending, value: { rule: rule })
          next
        end

        before_state = state(rule)
        rule.update!(
          status: "pending_revoke",
          revoked_by: @actor,
          revoke_reason: @reason,
          revoke_idempotency_key_digest: digest
        )
        delivery = Minecraft::EnqueueConsoleCommand.call(
          server: @server,
          command: revoke_command,
          delivery_prefix: "player-access-#{rule.public_id}-revoke"
        )
        unless delivery.success?
          rule.update!(
            status: "active",
            revoked_by: nil,
            revoke_reason: nil,
            revoke_idempotency_key_digest: nil
          )
          audit(rule, "minecraft.player_access_rule.revoke_failed", before_state:, after_state: state(rule))
          outcome = ServiceResult.failure(
            error: delivery.error || :minecraft_access_rule_delivery_failed,
            code: :minecraft_access_rule_delivery_failed,
            value: { rule: rule }
          )
          next
        end

        task = delivery.value.fetch(:task)
        rule.update!(revoke_task: task)
        audit(rule, "minecraft.player_access_rule.revoke_queued", before_state:, after_state: state(rule))
        Minecraft::ReconcilePlayerAccessRule.call(task:) if task.completed? || task.failed?
        outcome = success(rule.reload, replayed: false, noop: false)
      end
      outcome
    end

    def resolve_rule_for_revoke
      return @rule if @rule&.minecraft_server_id == @server.id

      effective_rule_scope.first
    end

    def effective_rule_scope
      Minecraft::PlayerAccessRule.effective
        .where(server: @server, rule_type: @rule_type)
        .where("lower(username) = ?", @username.downcase)
    end

    def equivalent_apply?(rule)
      rule.reason == @reason &&
        rule.player_uuid.to_s == normalized_uuid.to_s &&
        rule.expires_at&.to_i == @expires_at&.to_i
    end

    def apply_command
      return "whitelist add #{@username}" if @rule_type == "whitelist"

      "ban #{@username} #{@reason}"
    end

    def revoke_command
      return "whitelist remove #{@username}" if @rule_type == "whitelist"

      "pardon #{@username}"
    end

    def idempotency_digest(operation)
      Digest::SHA256.hexdigest(
        [ operation, @server.id, @rule_type, @username.downcase, @actor&.id || "system", @idempotency_key ].join(":")
      )
    end

    def replay_after_conflict
      operation = @desired_state ? "apply" : "revoke"
      column = @desired_state ? :apply_idempotency_key_digest : :revoke_idempotency_key_digest
      replay = Minecraft::PlayerAccessRule.find_by(column => idempotency_digest(operation))
      return replay_result(replay, operation: operation.to_sym) if replay

      existing = effective_rule_scope.first
      failure(:minecraft_access_rule_conflict, value: { rule: existing })
    end

    def replay_result(rule, operation:)
      if rule.failed? || (operation == :revoke && rule.active? && rule.revoke_task&.failed?)
        return failure(:minecraft_access_rule_delivery_failed, value: { rule: rule })
      end

      success(rule, replayed: true, noop: true)
    end

    def success(rule, replayed:, noop:)
      ServiceResult.success(rule: rule, replayed: replayed, noop: noop)
    end

    def failure(error, value: nil)
      ServiceResult.failure(error: error, code: error, value: value)
    end

    def state(rule)
      {
        status: rule.status,
        rule_type: rule.rule_type,
        username: rule.username,
        expires_at: rule.expires_at&.iso8601,
        apply_task_id: rule.apply_task_id,
        revoke_task_id: rule.revoke_task_id
      }
    end

    def audit(rule, action, before_state:, after_state:)
      Administration::AuditLogger.call(
        actor: @actor,
        action: action,
        resource: rule,
        reason: @reason,
        before_state: before_state,
        after_state: after_state,
        metadata: { server_id: @server.public_id },
        **@request_context
      )
    end
  end
end
