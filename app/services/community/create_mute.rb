# frozen_string_literal: true

module Community
  class CreateMute < ApplicationService
    def initialize(actor:, user:, section: nil, reason: nil, expires_at: nil)
      @actor = actor
      @user = user
      @section = section
      @reason = reason
      @expires_at = expires_at
    end

    def call
      unless @actor.permission?("forum.users.mute")
        return ServiceResult.failure(error: "Not authorized to mute users.")
      end

      mute = Community::Mute.create!(
        user: @user,
        section: @section,
        reason: @reason,
        expires_at: @expires_at,
        created_by: @actor
      )

      Administration::AuditLogger.call(
        actor: @actor,
        action: "forum.user.silence",
        resource: @user,
        reason: @reason,
        metadata: { section: @section&.slug, mute_id: mute.id, expires_at: @expires_at }.compact
      )
      ServiceResult.success(mute)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
