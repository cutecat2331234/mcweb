# frozen_string_literal: true

module Administration
  class UnbanUser < ApplicationService
    def initialize(user:, actor:)
      @user = user
      @actor = actor
    end

    def call
      @user.unban!
      AuditLogger.call(actor: @actor, action: "admin.user_unbanned", resource: @user)
      ServiceResult.success(@user)
    end
  end
end
