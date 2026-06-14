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

      ServiceResult.success(mute)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
