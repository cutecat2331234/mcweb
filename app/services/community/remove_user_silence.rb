# frozen_string_literal: true

module Community
  class RemoveUserSilence < ApplicationService
    def initialize(actor:, user:)
      @actor = actor
      @user = user
    end

    def call
      unless @actor.permission?("forum.users.mute") || @actor.permission?("admin.access")
        return ServiceResult.failure(error: "无权解除禁言。")
      end

      Community::UserSilence.active.where(user: @user).destroy_all
      ServiceResult.success
    end
  end
end
