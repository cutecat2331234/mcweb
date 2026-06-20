# frozen_string_literal: true

module Community
  class CreateUserSilence < ApplicationService
    def initialize(actor:, user:, reason: nil, expires_at: nil, days: nil)
      @actor = actor
      @user = user
      @reason = reason.to_s.strip.presence
      @expires_at = expires_at || (days.to_i.positive? ? days.to_i.days.from_now : nil)
    end

    def call
      unless @actor.permission?("forum.users.mute") || @actor.permission?("admin.access")
        return ServiceResult.failure(error: "silence_user_unauthorized")
      end

      silence = Community::UserSilence.create!(
        user: @user,
        created_by: @actor,
        reason: @reason,
        expires_at: @expires_at
      )

      ServiceResult.success(silence)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
