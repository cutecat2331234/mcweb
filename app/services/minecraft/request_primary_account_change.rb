# frozen_string_literal: true

require "digest"

module Minecraft
  class RequestPrimaryAccountChange < ApplicationService
    def initialize(user:, target_identity_link:, actor:, reason:, idempotency_key:)
      @user = user
      @target_identity_link = target_identity_link
      @actor = actor
      @reason = reason.to_s.strip
      @idempotency_key = idempotency_key.to_s
    end

    def call
      return failure(:primary_account_forbidden) unless @actor&.id == @user.id
      return failure(:primary_account_idempotency_required) if @idempotency_key.blank?

      target = Minecraft::IdentityLink.active.find_by(
        id: @target_identity_link&.id,
        user_id: @user.id
      )
      return failure(:minecraft_account_not_bound) unless target

      replay = idempotent_replay(target)
      return replay if replay

      policy = Minecraft::PrimaryAccountPolicy.snapshot(user: @user)
      if policy.cooldown_remaining_seconds.positive?
        return ServiceResult.failure(
          error: :primary_account_cooldown_active,
          code: :primary_account_cooldown_active,
          value: { cooldown_remaining_seconds: policy.cooldown_remaining_seconds }
        )
      end

      case policy.switch_policy
      when "immediate"
        Minecraft::ApplyPrimaryAccountChange.call(
          user: @user,
          target_identity_link: target,
          actor: @actor,
          change_source: "player_immediate",
          idempotency_key: @idempotency_key,
          reason: @reason.presence,
          enforce_cooldown: true,
          counts_for_cooldown: true
        )
      when "staff_approval"
        create_approval_request(target, policy)
      when "administrator_only"
        failure(:primary_account_administrator_only)
      else
        failure(:primary_account_policy_invalid)
      end
    end

    private

    def idempotent_replay(target)
      digest = Digest::SHA256.hexdigest(@idempotency_key)
      event = Minecraft::PrimaryAccountChangeEvent.find_by(
        user: @user,
        idempotency_key_digest: digest
      )
      if event
        return failure(:primary_account_idempotency_conflict) unless event.to_identity_link_id == target.id
        return failure(:primary_account_idempotency_conflict) unless event.change_source == "player_immediate"

        return ServiceResult.success(
          event: event,
          identity_link: event.to_identity_link,
          changed: false,
          replayed: true
        )
      end

      request_record = Minecraft::PrimaryAccountChangeRequest.find_by(
        user: @user,
        idempotency_key_digest: digest
      )
      return unless request_record
      return failure(:primary_account_idempotency_conflict) unless request_record.target_identity_link_id == target.id

      ServiceResult.success(request: request_record, changed: false, replayed: true)
    end

    def create_approval_request(target, policy)
      return failure(:primary_account_reason_required) if @reason.blank?
      return failure(:primary_account_reason_too_long) if @reason.length > 2_000

      digest = Digest::SHA256.hexdigest(@idempotency_key)
      created = false
      request_record = nil

      ActiveRecord::Base.transaction do
        @user.lock!
        Minecraft::ExpirePrimaryAccountChangeRequests.call(user: @user)

        replay = Minecraft::PrimaryAccountChangeRequest.find_by(
          user: @user,
          idempotency_key_digest: digest
        )
        if replay
          raise IdempotencyConflict unless replay.target_identity_link_id == target.id

          request_record = replay
          next
        end

        raise AlreadyPrimary if target.reload.primary_account?

        if Minecraft::PrimaryAccountChangeRequest.pending.exists?(user: @user)
          raise PendingRequestExists
        end

        source = Minecraft::IdentityLink.primary.find_by(user: @user)
        raise MissingPrimary unless source

        now = Time.current
        request_record = Minecraft::PrimaryAccountChangeRequest.create!(
          user: @user,
          source_identity_link: source,
          target_identity_link: target,
          requested_by: @actor,
          request_reason: @reason,
          policy_snapshot: "staff_approval",
          idempotency_key_digest: digest,
          requested_at: now,
          expires_at: now + policy.request_expiry_hours.hours
        )
        Administration::AuditLogger.call(
          actor: @actor,
          action: "minecraft.primary_account_change_requested",
          resource: request_record,
          request_id: @idempotency_key.first(100),
          reason: @reason,
          metadata: {
            user_id: @user.id,
            source_identity_link_id: source.id,
            target_identity_link_id: target.id,
            expires_at: request_record.expires_at.iso8601
          }
        )
        created = true
      end

      Minecraft::PrimaryAccountNotifications.request_created(request_record) if created
      ServiceResult.success(request: request_record, changed: false, replayed: !created)
    rescue PendingRequestExists
      failure(:primary_account_request_pending)
    rescue MissingPrimary
      failure(:primary_account_missing)
    rescue AlreadyPrimary
      failure(:minecraft_account_already_primary)
    rescue IdempotencyConflict
      failure(:primary_account_idempotency_conflict)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      ServiceResult.failure(
        error: :primary_account_request_conflict,
        code: :primary_account_request_conflict,
        errors: error.respond_to?(:record) ? error.record&.errors&.to_hash : nil
      )
    end

    class PendingRequestExists < StandardError; end
    class MissingPrimary < StandardError; end
    class AlreadyPrimary < StandardError; end
    class IdempotencyConflict < StandardError; end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
