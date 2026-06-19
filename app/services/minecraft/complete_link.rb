# frozen_string_literal: true

module Minecraft
  class CompleteLink < ApplicationService
    def initialize(user:, code:)
      @user = user
      @code = code.to_s.strip.upcase
    end

    def call
      link_code = Minecraft::LinkCode
        .where(code_digest: digest_code(@code), used_at: nil)
        .where("expires_at > ?", Time.current)
        .first

      return ServiceResult.failure(error: "Invalid or expired link code.") unless link_code

      identity = nil
      player_ref = nil
      ActiveRecord::Base.transaction do
        link_code.lock!
        return ServiceResult.failure(error: "Link code has already been used.") if link_code.used_at?

        player_ref = PlayerRef.resolve(
          uuid: link_code.minecraft_uuid,
          platform: link_code.identity_type,
          username: link_code.minecraft_username,
          identity_type: link_code.identity_type
        )

        if player_ref.website_user && player_ref.website_user.id != @user.id
          return ServiceResult.failure(error: "This Minecraft account is already linked.")
        end

        existing = Minecraft::Identity.find_by(uuid: link_code.minecraft_uuid, identity_type: link_code.identity_type)
        if existing && existing.user_id != @user.id
          return ServiceResult.failure(error: "This Minecraft account is already linked.")
        end

        identity = existing || Minecraft::Identity.create!(
          user: @user,
          player_profile: player_ref.profile,
          uuid: link_code.minecraft_uuid,
          username: link_code.minecraft_username,
          identity_type: link_code.identity_type,
          server: link_code.server,
          linked_at: Time.current
        )
        identity.update!(user: @user, player_profile: player_ref.profile) if existing

        player_ref.link_user!(@user) unless player_ref.website_user

        link_code.update!(used_at: Time.current, used_by: @user)
      end

      Administration::AuditLogger.call(
        actor: @user,
        action: "minecraft.identity_linked",
        resource: identity,
        metadata: { uuid: identity.uuid, username: identity.username, player_id: player_ref.public_id }
      )

      Minecraft::Integration::ActionRunner.call(
        event_key: "player.link_completed",
        event_id: "link-#{identity.id}-#{Time.current.to_i}",
        payload: { player_id: player_ref.public_id, uuid: identity.uuid, username: identity.username }
      )

      ServiceResult.success(identity)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    rescue ArgumentError => e
      ServiceResult.failure(error: e.message)
    end

    private

    def digest_code(code)
      Minecraft::LinkCode.digest_code(code)
    end
  end
end
