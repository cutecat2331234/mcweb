# frozen_string_literal: true

module Administration
  class BanUser < ApplicationService
    def initialize(user:, actor:, reason: nil, expires_at: nil)
      @user = user
      @actor = actor
      @reason = reason
      @expires_at = expires_at
    end

    def call
      return ServiceResult.failure(error: "Cannot ban yourself.") if @actor.id == @user.id

      @user.ban!(reason: @reason, expires_at: @expires_at)
      Session.where(user: @user, revoked_at: nil).find_each(&:revoke!)
      AuditLogger.call(actor: @actor, action: "admin.user_banned", resource: @user)
      ServiceResult.success(@user)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
