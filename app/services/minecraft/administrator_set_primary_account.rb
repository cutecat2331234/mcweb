# frozen_string_literal: true

module Minecraft
  class AdministratorSetPrimaryAccount < ApplicationService
    def initialize(user:, target_identity_link:, actor:, reason:, idempotency_key:)
      @user = user
      @target_identity_link = target_identity_link
      @actor = actor
      @reason = reason.to_s.strip
      @idempotency_key = idempotency_key.to_s
    end

    def call
      result = Minecraft::ApplyPrimaryAccountChange.call(
        user: @user,
        target_identity_link: @target_identity_link,
        actor: @actor,
        change_source: "administrator_override",
        idempotency_key: @idempotency_key,
        reason: @reason,
        enforce_cooldown: false,
        counts_for_cooldown: false
      )
      return result unless result.success?

      unless result.value.fetch(:replayed)
        Minecraft::PrimaryAccountNotifications.administrator_override(result.value.fetch(:event))
      end
      result
    end
  end
end
