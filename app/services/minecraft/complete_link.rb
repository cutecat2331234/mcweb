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
      ActiveRecord::Base.transaction do
        link_code.lock!
        return ServiceResult.failure(error: "Link code has already been used.") if link_code.used_at?

        if Minecraft::Identity.exists?(uuid: link_code.minecraft_uuid, identity_type: link_code.identity_type)
          return ServiceResult.failure(error: "This Minecraft account is already linked.")
        end

        identity = Minecraft::Identity.create!(
          user: @user,
          uuid: link_code.minecraft_uuid,
          username: link_code.minecraft_username,
          identity_type: link_code.identity_type,
          server: link_code.server,
          linked_at: Time.current
        )

        link_code.update!(used_at: Time.current, used_by: @user)
      end

      Administration::AuditLogger.call(
        actor: @user,
        action: "minecraft.identity_linked",
        resource: identity,
        metadata: { uuid: identity.uuid, username: identity.username }
      )

      ServiceResult.success(identity)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def digest_code(code)
      Minecraft::LinkCode.digest_code(code)
    end
  end
end
