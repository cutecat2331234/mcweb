# frozen_string_literal: true

require "digest"

module Minecraft
  class ApplyPrimaryAccountChange < ApplicationService
    SOURCES = %w[player_immediate staff_approval administrator_override].freeze

    def initialize(
      user:,
      target_identity_link:,
      actor:,
      change_source:,
      idempotency_key:,
      reason: nil,
      request_record: nil,
      enforce_cooldown: true,
      counts_for_cooldown: true
    )
      @user = user
      @target_identity_link = target_identity_link
      @actor = actor
      @change_source = change_source.to_s
      @idempotency_key = idempotency_key.to_s
      @reason = reason.to_s.strip.presence
      @request_record = request_record
      @enforce_cooldown = enforce_cooldown
      @counts_for_cooldown = counts_for_cooldown
    end

    def call
      authorization_error = authorize
      return ServiceResult.failure(error: authorization_error, code: authorization_error) if authorization_error
      return failure(:primary_account_idempotency_required) if @idempotency_key.blank?

      digest = Digest::SHA256.hexdigest(@idempotency_key)
      result_value = nil

      ActiveRecord::Base.transaction do
        @user.lock!
        replay = Minecraft::PrimaryAccountChangeEvent.find_by(
          user: @user,
          idempotency_key_digest: digest
        )
        if replay
          unless replay.to_identity_link_id == @target_identity_link&.id && replay.change_source == @change_source
            raise IdempotencyConflict
          end

          result_value = { event: replay, identity_link: replay.to_identity_link, changed: false, replayed: true }
          next
        end

        target = Minecraft::IdentityLink.active.find_by(
          id: @target_identity_link&.id,
          user_id: @user.id
        )
        raise InvalidTarget unless target
        raise AlreadyPrimary if target.primary_account?

        if @enforce_cooldown
          policy = Minecraft::PrimaryAccountPolicy.snapshot(user: @user)
          raise CooldownActive, policy.cooldown_remaining_seconds if policy.cooldown_remaining_seconds.positive?
        end

        set_result = Minecraft::SetPrimaryAccount.call(
          user: @user,
          identity_link: target,
          actor: @actor,
          request_id: @idempotency_key.first(100),
          reason: @reason,
          change_source: @change_source
        )
        raise ApplyFailed, set_result unless set_result.success?

        event = Minecraft::PrimaryAccountChangeEvent.create!(
          user: @user,
          from_identity_link: set_result.value[:previous_identity_link],
          to_identity_link: target,
          actor: @actor,
          primary_account_change_request: @request_record,
          change_source: @change_source,
          idempotency_key_digest: digest,
          reason: @reason,
          counts_for_cooldown: @counts_for_cooldown,
          changed_at: Time.current
        )
        result_value = { event: event, identity_link: target.reload, changed: true, replayed: false }
      end

      ServiceResult.success(result_value)
    rescue InvalidTarget
      failure(:minecraft_account_not_bound)
    rescue AlreadyPrimary
      failure(:minecraft_account_already_primary)
    rescue IdempotencyConflict
      failure(:primary_account_idempotency_conflict)
    rescue CooldownActive => error
      ServiceResult.failure(
        error: :primary_account_cooldown_active,
        code: :primary_account_cooldown_active,
        value: { cooldown_remaining_seconds: error.remaining_seconds }
      )
    rescue ApplyFailed => error
      error.result
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ActiveRecord::StaleObjectError => error
      ServiceResult.failure(
        error: :primary_account_conflict,
        code: :primary_account_conflict,
        errors: error.respond_to?(:record) ? error.record&.errors&.to_hash : nil
      )
    end

    private

    class InvalidTarget < StandardError; end
    class AlreadyPrimary < StandardError; end
    class IdempotencyConflict < StandardError; end
    class CooldownActive < StandardError
      attr_reader :remaining_seconds

      def initialize(remaining_seconds)
        @remaining_seconds = remaining_seconds
        super()
      end
    end
    class ApplyFailed < StandardError
      attr_reader :result

      def initialize(result)
        @result = result
        super()
      end
    end

    def authorize
      return :primary_account_change_source_invalid unless @change_source.in?(SOURCES)
      return :primary_account_actor_required unless @actor

      case @change_source
      when "player_immediate"
        return :primary_account_forbidden unless @actor.id == @user.id
      when "staff_approval"
        return :primary_account_forbidden unless @actor.permission?("minecraft.primary_accounts.review")
      when "administrator_override"
        return :primary_account_forbidden unless @actor.permission?("minecraft.primary_accounts.switch_for_user")
        return :primary_account_reason_required if @reason.blank?
      end

      nil
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
