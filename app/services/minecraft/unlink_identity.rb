# frozen_string_literal: true

require "digest"

module Minecraft
  class UnlinkIdentity < ApplicationService
    def initialize(user:, identity_link:, actor:, confirmation:, lock_version:, idempotency_key:,
                   ip_address: nil, user_agent: nil)
      @user = user
      @identity_link = identity_link
      @actor = actor
      @confirmation = confirmation.to_s.strip
      @lock_version = Integer(lock_version, exception: false)
      @idempotency_key = idempotency_key.to_s.strip
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return failure(:minecraft_identity_unlink_forbidden) unless @user && @actor&.id == @user.id
      return failure(:minecraft_identity_unlink_idempotency_required) if @idempotency_key.blank?
      return failure(:minecraft_identity_unlink_lock_version_required) if @lock_version.nil?
      return failure(:minecraft_identity_unlink_confirmation_required) if @confirmation.blank?

      digest = idempotency_digest
      result = nil

      Minecraft::IdentityLink.transaction do
        @user.lock!
        link = Minecraft::IdentityLink.lock.find_by(id: @identity_link&.id, user_id: @user.id)
        return failure(:minecraft_identity_unlink_account_not_bound) unless link

        replay = idempotent_replay(link, digest)
        return replay if replay
        return failure(:minecraft_identity_unlink_inactive) if link.unlinked_at.present?
        return failure(:minecraft_identity_unlink_stale) unless link.lock_version == @lock_version

        identity = link.player_profile.active_identity
        return failure(:minecraft_identity_unlink_target_unavailable) unless identity
        return failure(:minecraft_identity_unlink_confirmation_mismatch) unless confirmed?(identity.username)

        restriction = Minecraft::IdentityUnlinkRestrictions.check(user: @user, identity_link: link)
        return restriction if restriction.failure?

        was_primary = link.primary_account?
        pending_request_ids = pending_request_ids_for(link)
        before_state = identity_snapshot(link, identity)

        link.update!(unlink_idempotency_key_digest: digest)
        link.unlink!
        successor = was_primary ? Minecraft::IdentityLink.primary.find_by(user_id: @user.id) : nil

        Administration::AuditLogger.call(
          actor: @actor,
          action: "minecraft.identity_unlinked",
          resource: link.player_profile,
          request_id: "minecraft-unlink-#{digest.first(32)}",
          before_state: before_state,
          after_state: {
            active: false,
            unlinked_at: link.unlinked_at&.iso8601,
            successor_identity_link_id: successor&.id
          },
          metadata: {
            user_id: @user.id,
            identity_link_id: link.id,
            player_id: link.player_profile.public_id,
            username: identity.username,
            identity_type: identity.identity_type,
            was_primary: was_primary,
            successor_identity_link_id: successor&.id,
            cancelled_primary_account_request_ids: pending_request_ids
          }.compact,
          ip_address: @ip_address,
          user_agent: @user_agent
        )

        result = ServiceResult.success(
          identity_link: link.reload,
          changed: true,
          replayed: false,
          successor_identity_link: successor,
          cancelled_request_ids: pending_request_ids
        )
      end

      result
    rescue ActiveRecord::StaleObjectError
      failure(:minecraft_identity_unlink_stale)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      failure(:minecraft_identity_unlink_conflict)
    end

    private

    def idempotency_digest
      Digest::SHA256.hexdigest(@idempotency_key)
    end

    def idempotent_replay(link, digest)
      existing = Minecraft::IdentityLink.find_by(
        user_id: @user.id,
        unlink_idempotency_key_digest: digest
      )
      return unless existing
      return failure(:minecraft_identity_unlink_idempotency_conflict) unless existing.id == link.id
      return failure(:minecraft_identity_unlink_idempotency_conflict) unless existing.user_id == @user.id
      return failure(:minecraft_identity_unlink_idempotency_conflict) if existing.unlinked_at.nil?

      ServiceResult.success(
        identity_link: existing,
        changed: false,
        replayed: true,
        successor_identity_link: Minecraft::IdentityLink.primary.find_by(user_id: @user.id),
        cancelled_request_ids: []
      )
    end

    def confirmed?(username)
      expected = username.to_s.strip
      expected.present? && @confirmation.bytesize == expected.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(@confirmation, expected)
    end

    def pending_request_ids_for(link)
      Minecraft::PrimaryAccountChangeRequest.pending
        .where(
          "target_identity_link_id = :id OR source_identity_link_id = :id",
          id: link.id
        )
        .order(:id)
        .pluck(:id)
    end

    def identity_snapshot(link, identity)
      {
        active: true,
        primary_account: link.primary_account?,
        player_id: link.player_profile.public_id,
        username: identity.username,
        uuid: identity.external_uuid,
        identity_type: identity.identity_type
      }
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
