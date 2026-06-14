# frozen_string_literal: true

module Community
  class ToggleUserBlock < ApplicationService
    def initialize(blocker:, blocked_username:)
      @blocker = blocker
      @blocked = User.find_by(username: blocked_username.to_s.strip)
    end

    def call
      return ServiceResult.failure(error: "User not found.") unless @blocked
      return ServiceResult.failure(error: "You cannot block yourself.") if @blocker.id == @blocked.id

      existing = Community::UserBlock.find_by(blocker: @blocker, blocked: @blocked)
      if existing
        existing.destroy!
        ServiceResult.success(blocked: false)
      else
        Community::UserBlock.create!(blocker: @blocker, blocked: @blocked)
        ServiceResult.success(blocked: true)
      end
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
