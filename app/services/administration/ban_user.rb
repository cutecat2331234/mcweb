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
      return ServiceResult.failure(error: :cannot_ban_yourself) if @actor.id == @user.id
      return ServiceResult.failure(error: :cannot_ban_site_owner) if @user.account_owner? && !@actor.account_owner?

      @user.ban!(reason: @reason, expires_at: @expires_at)
      Session.where(user: @user, revoked_at: nil).find_each(&:revoke!)
      Administration::ApiKey.where(user: @user, revoked_at: nil)
        .update_all(revoked_at: Time.current, updated_at: Time.current)
      AuditLogger.call(actor: @actor, action: "admin.user_banned", resource: @user)
      Mcweb::Events.publish("identity.user.banned", user: @user, actor: @actor, reason: @reason)
      ServiceResult.success(@user)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
