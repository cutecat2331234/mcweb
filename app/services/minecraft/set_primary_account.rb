# frozen_string_literal: true

module Minecraft
  class SetPrimaryAccount < ApplicationService
    def initialize(user:, identity_link:, actor: nil, request_id: nil, reason: nil, change_source: nil)
      @user = user
      @identity_link = identity_link
      @actor = actor || user
      @request_id = request_id
      @reason = reason.to_s.strip.presence
      @change_source = change_source.to_s.strip.presence
    end

    def call
      return ServiceResult.failure(error: :minecraft_account_not_bound) unless @identity_link

      link = Minecraft::IdentityLink.active.find_by(
        id: @identity_link.id,
        user_id: @user.id
      )
      return ServiceResult.failure(error: :minecraft_account_not_bound) unless link

      changed = false
      previous_profile_id = nil
      previous_link = nil

      @user.with_lock do
        link.lock!
        unless link.primary_account?
          previous_link = Minecraft::IdentityLink.primary.find_by(user_id: @user.id)
          previous_profile_id = previous_link&.player_profile&.public_id

          Minecraft::IdentityLink.active
                                 .where(user_id: @user.id, primary_account: true)
                                 .update_all(primary_account: false, updated_at: Time.current)
          link.update!(primary_account: true)

          Administration::AuditLogger.call(
            actor: @actor,
            action: "minecraft.primary_account_changed",
            resource: link.player_profile,
            request_id: @request_id,
            reason: @reason,
            before_state: { player_id: previous_profile_id },
            after_state: { player_id: link.player_profile.public_id },
            metadata: {
              user_id: @user.id,
              from_identity_link_id: previous_link&.id,
              to_identity_link_id: link.id,
              change_source: @change_source
            }.compact
          )
          changed = true
        end
      end

      ServiceResult.success(
        identity_link: link.reload,
        player_profile: link.player_profile,
        previous_identity_link: previous_link,
        changed: changed
      )
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      ServiceResult.failure(errors: e.record&.errors&.to_hash, error: :primary_account_conflict)
    end
  end
end
